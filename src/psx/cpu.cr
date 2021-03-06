require "sdl"
require "./cop0"

class CPU
  @regs : Array(UInt32)
  @out_regs : Array(UInt32)
  @hi : UInt32
  @lo : UInt32
  @next_pc : UInt32

  enum Exception : UInt32
    Interrupt = 0x0
    LoadAddressError= 0x4
    StoreAddressError = 0x5
    SysCall = 0x8
    Break = 0x9
    IllegalInstruction = 0xA
    CoprocessorError = 0xB
    Overflow = 0xC
  end

  PROCESSOR_ID = 0x00000002_u32

  def initialize(bus : Bus, irq : InterruptState, counters : Counters, timers : Timers, sideloadfile : String, sideload : Bool, fastboot : Bool)
    @sideload = sideload
    @sideloadfile = sideloadfile
    @fastboot = fastboot
    @counters = counters
    @timers = timers
    @irq = irq
    @cop0 = Cop0.new(irq)
    @pc = 0xBFC00000_u32
    @next_pc = @pc &+ 4
    @bus = bus
    @function = 0_u32
    @t = 0_u32
    @imm = 0_u32
    @s = 0_u32
    @d = 0_u32
    @hi = 0xDEADBEEF_u32
    @lo = 0xDEADBEEF_u32
    @subfunction = 0_u32
    @shift = 0_u32
    @regs = Array.new 32, 0xDEADBEEF_u32
    @regs[0] = 0
    @out_regs = Array.new 32, 0_u32
    @load = {0_u32, 0_u32}
    @next_instruction = 0_u32
    @current_pc = 0_u32
    @branchbool = false
    @delaybool = false
    @debug = false
    @logfile = File.open("./logfile.txt", "w")
    @cycle_count = 0
  end

  def drawframe
    @bus.drawframe
  end

  def load32(addr : UInt32) : UInt32
    if addr == 528488449
      @logfile.close
    end
    @bus.load32(addr)
  end

  def load16(addr : UInt32) : UInt16
    @bus.load16(addr)
  end

  def load8(addr : UInt32) : UInt8
    @bus.load8(addr)
  end

  def store32(addr : UInt32, val : UInt32)
    if @cop0.cache_isolated
      #puts "ignoring store while cache is isolated"
    else
      @bus.store32(addr, val)
    end
  end

  def store16(addr : UInt32, val : UInt16)
    @bus.store16(addr, val)
  end

  def store8(addr : UInt32, val : UInt8)
    @bus.store8(addr, val)
  end

  def imm_jump(instruction) : UInt32
    instruction & 0x3FFFFFF
  end

  def imm_se(instruction : UInt32)
    v = (instruction & 0xFFFF).to_i16!
    v.to_u32
  end

  def branch(offset : UInt32)
    offset = (offset << 2)
    pc = @next_pc
    pc &+= offset
    pc -= 4
    @next_pc = pc
    @branchbool = true
  end

  def run_next_instruction
    if @pc == 0x80030000 && @sideload
      @bus.ram.sideload(@sideloadfile)
      @pc = @bus.ram.pc
      @next_pc = @pc &+ 4
      @sideload = false
      @debug = false
    elsif @pc == 0x80030000 && @fastboot && @branchbool == false
      puts "Fastbooting!"
      @pc = read_reg(31)
      puts "New PC: 0x#{@pc.to_s(16)}"
      @next_pc = @pc &+ 4
      @fastboot = false
    end


    @current_pc = @pc
    if @current_pc % 4 != 0
      exception(Exception::LoadAddressError, @current_pc, @branchbool)
    end

    pc = @pc
    instruction = load32(pc)

    if @debug
      @logfile.write("#{pc.to_s(16)} #{instruction.to_s(16)} \n".to_slice)
    end

    @pc = @next_pc
    @next_pc = @pc &+ 4
    @delaybool = @branchbool
    @branchbool = false

    @cycle_count += 1
    if @cycle_count.remainder(8) == 0
      @timers.tick
    end

    if @cop0.irq_active
      @counters.cpu_interrupt.increment
      exception(Exception::Interrupt, @current_pc, @branchbool)
    else
      @irq.tick
      decode_and_execute(instruction)
    end


    reg, val = @load
    set_reg(reg, val)
    @load = {0_u32, 0_u32}

    @regs = @out_regs.clone
    if @pc == 0xB0 && @regs[9] == 0x3D
      print @regs[4].chr
    end
  end

  def read_reg(index : UInt32) : UInt32
    @regs[index]
  end

  def set_reg(index : UInt32, val : UInt32)
    @out_regs[index] = val
    @out_regs[0] = 0
  end

  def decode_and_execute(instruction : UInt32)
    @function = instruction >> 26
    @t = (instruction >> 16) & 0x1F
    @imm = instruction & 0xFFFF
    @s = (instruction >> 21) & 0x1F
    @d = (instruction >> 11) & 0x1F
    @subfunction = instruction & 0x3F
    @shift = (instruction >> 6) & 0x1F

    case @function
    when 0b000000
      case @subfunction
      when 0b000000 then op_sll(instruction)
      when 0b000010 then op_srl(instruction)
      when 0b000011 then op_sra(instruction)
      when 0b000100 then op_sllv(instruction)
      when 0b000110 then op_srlv(instruction)
      when 0b000111 then op_srav(instruction)
      when 0b001000 then op_jr(instruction)
      when 0b001001 then op_jalr(instruction)
      when 0b001100 then op_syscall(instruction)
      when 0b001101 then op_break(instruction)
      when 0b010000 then op_mfhi(instruction)
      when 0b010001 then op_mthi(instruction)
      when 0b010010 then op_mflo(instruction)
      when 0b010011 then op_mtlo(instruction)
      when 0b011000 then op_mult(instruction)
      when 0b011001 then op_multu(instruction)
      when 0b011010 then op_div(instruction)
      when 0b011011 then op_divu(instruction)
      when 0b100000 then op_add(instruction)
      when 0b100001 then op_addu(instruction)
      when 0b100010 then op_sub(instruction)
      when 0b100011 then op_subu(instruction)
      when 0b100100 then op_and(instruction)
      when 0b100101 then op_or(instruction)
      when 0b100110 then op_xor(instruction)
      when 0b100111 then op_nor(instruction)
      when 0b101010 then op_slt(instruction)
      when 0b101011 then op_sltu(instruction)
      else op_illegal(instruction)
      end
    when 0b000001 then op_bxx(instruction)
    when 0b000010 then op_j(instruction)
    when 0b000011 then op_jal(instruction)
    when 0b000100 then op_beq(instruction)
    when 0b000101 then op_bne(instruction)
    when 0b000110 then op_blez(instruction)
    when 0b000111 then op_bgtz(instruction)
    when 0b001000 then op_addi(instruction)
    when 0b001001 then op_addiu(instruction)
    when 0b001010 then op_slti(instruction)
    when 0b001011 then op_sltiu(instruction)
    when 0b001100 then op_andi(instruction)
    when 0b001101 then op_ori(instruction)
    when 0b001110 then op_xori(instruction)
    when 0b001111 then op_lui(instruction)
    when 0b010000 then op_cop0(instruction)
    when 0b010001 then op_cop1(instruction)
    when 0b010010 then op_cop2(instruction)
    when 0b010011 then op_cop3(instruction)
    when 0b100000 then op_lb(instruction)
    when 0b100001 then op_lh(instruction)
    when 0b100010 then op_lwl(instruction)
    when 0b100011 then op_lw(instruction)
    when 0b100100 then op_lbu(instruction)
    when 0b100101 then op_lhu(instruction)
    when 0b100110 then op_lwr(instruction)
    when 0b101000 then op_sb(instruction)
    when 0b101001 then op_sh(instruction)
    when 0b101010 then op_swl(instruction)
    when 0b101011 then op_sw(instruction)
    when 0b101110 then op_swr(instruction)
    when 0b110000 then op_lwc0(instruction)
    when 0b110001 then op_lwc1(instruction)
    when 0b110010 then op_lwc2(instruction)
    when 0b110011 then op_lwc3(instruction)
    when 0b111000 then op_swc0(instruction)
    when 0b111001 then op_swc1(instruction)
    when 0b111010 then op_swc2(instruction)
    when 0b111011 then op_swc3(instruction)
    else op_illegal(instruction)
    end
  end

  def exception(cause : Exception, pc : UInt32, delaybool : Bool)
    handler_addr = @cop0.exception(cause, pc, delaybool)
    @pc = handler_addr
    @next_pc = @pc &+ 4
  end

  def op_illegal(instruction)
    puts "Illegal instruction 0x#{instruction.to_s(16)}"
    exception(Exception::IllegalInstruction, @current_pc, @delaybool)
  end

  def op_swc3(instruction)
    exception(Exception::CoprocessorError, @current_pc, @delaybool)
  end

  def op_swc2(instruction)
    raise "unhandled GTE SWC 0x#{instruction.to_s(16)}"
  end

  def op_swc1(instruction)
    exception(Exception::CoprocessorError, @current_pc, @delaybool)
  end

  def op_swc0(instruction)
    exception(Exception::CoprocessorError, @current_pc, @delaybool)
  end


  def op_lwc3(instruction)
    exception(Exception::CoprocessorError, @current_pc, @delaybool)
  end

  def op_lwc2(instruction)
    raise "unhandled GTE LWC 0x#{instruction.to_s(16)}"
  end

  def op_lwc1(instruction)
    exception(Exception::CoprocessorError, @current_pc, @delaybool)
  end

  def op_lwc0(instruction)
    exception(Exception::CoprocessorError, @current_pc, @delaybool)
  end

  def op_swr(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    addr = read_reg(s) &+ i
    v = read_reg(t)
    aligned_addr = addr & ~3
    cur_mem = load32(aligned_addr)
    case addr & 3
    when 0 then mem = (cur_mem & 0x00000000) | (v << 0)
    when 1 then mem = (cur_mem & 0x000000FF) | (v << 8)
    when 2 then mem = (cur_mem & 0x0000FFFF) | (v << 16)
    when 3 then mem = (cur_mem & 0x00FFFFFF) | (v << 24)
    else
      raise "SWR unreachable!"
    end
    store32(aligned_addr, mem)
  end

  def op_swl(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    addr = read_reg(s) &+ i
    v = read_reg(t)
    aligned_addr = addr & ~3
    cur_mem = load32(aligned_addr)
    case addr & 3
    when 0 then mem = (cur_mem & 0xFFFFFF00) | (v >> 24)
    when 1 then mem = (cur_mem & 0xFFFF0000) | (v >> 16)
    when 2 then mem = (cur_mem & 0xFF000000) | (v >> 8)
    when 3 then mem = (cur_mem & 0x00000000) | (v >> 0)
    else
      raise "SWL unreachable!"
    end
    store32(aligned_addr, mem)
  end

  def op_lwr(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    addr = read_reg(s) &+ i
    cur_v = @out_regs[t]
    aligned_addr = addr & ~3
    aligned_word = load32(aligned_addr)
    case addr & 3
    when 0 then v = (cur_v & 0x00000000) | (aligned_word >> 0)
    when 1 then v = (cur_v & 0xFF000000) | (aligned_word >> 8)
    when 2 then v = (cur_v & 0xFFFF0000) | (aligned_word >> 16)
    when 3 then v = (cur_v & 0xFFFFFF00) | (aligned_word >> 24)
    else
      raise "LWR unreachable!"
    end
    @load = {t, v}
  end

  def op_lwl(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    addr = read_reg(s) &+ i
    pending_reg = @load[0]
    pending_value = @load[1]
    if pending_value == t
      cur_v = pending_value
    else
      cur_v = read_reg(t)
    end

    aligned_addr = addr & ~3
    aligned_word = load32(aligned_addr)

    case addr & 3
    when 0 then v = (cur_v & 0x00FFFFFF) | (aligned_word << 24)
    when 1 then v = (cur_v & 0x0000FFFF) | (aligned_word << 16)
    when 2 then v = (cur_v & 0x000000FF) | (aligned_word << 8)
    when 3 then v = (cur_v & 0x00000000) | (aligned_word << 0)
    else raise "LWL unreachable!"
    end
    @load = {t, v}
  end

  def op_mfc2(instruction)
    cpu_r = @t
    cop_r = @d
    #v = gte.data(cop_r)
    #@load = {cpu_r, v}
    puts "mfc2"
  end

  def op_cfc2(instruction)
    puts "cfc2"
  end

  def op_mtc2(instruction)
    puts "mtc2"
  end

  def op_ctc2(instruction)
    puts "ctc2"
  end

  def op_cop2(instruction)
    if @s & 0x10 != 0
      raise "Unhandled GTE command"
    else
      case @s
      when 0b00000 then op_mfc2(instruction)
      when 0b00010 then op_cfc2(instruction)
      when 0b00100 then op_mtc2(instruction)
      when 0b00110 then op_ctc2(instruction)
      else raise "unhandled cop2 GTE instruction 0x#{instruction.to_s(16)}"
      end
    end
  end

  def op_cop3(instruction)
    exception(Exception::CoprocessorError, @current_pc, @delaybool)
  end

  def op_cop1(instruction)
    exception(Exception::CoprocessorError, @current_pc, @delaybool)
  end

  def op_xori(instruction)
    i = @imm
    t = @t
    s = @s
    v = read_reg(s) ^ i
    set_reg(t, v)
  end

  def op_sub(instruction)
    s = @s
    t = @t
    d = @d
    s = read_reg(s)
    t = read_reg(t)
    v = s &- t
    if ((v ^ s) & (s ^ t)) & 0x80000000 != 0
      exception(Exception::Overflow, @current_pc, @delaybool)
    else
      set_reg(d, v)
    end
  end

  def op_mult(instruction)
    s = @s
    t = @t
    a = read_reg(s).to_i32!.to_i64
    b = read_reg(t).to_i32!.to_i64
    v = (a * b).to_u64!
    @hi = (v >> 32).to_u32!
    @lo = v.to_u32!
  end

  def op_break(instruction)
    exception(Exception::Break, @current_pc, @delaybool)
  end

  def op_srlv(instruction)
    d = @d
    s = @s
    t = @t
    v = read_reg(t) >> (read_reg(s) & 0x1F)
    set_reg(d, v)
  end

  def op_srav(instruction)
    d = @d
    s = @s
    t = @t
    v = read_reg(t).to_i32! >> (read_reg(s) & 0x1F)
    set_reg(d, v.to_u32!)
  end

  def op_multu(instruction)
    s = @s
    t = @t
    a = read_reg(s).to_u64
    b = read_reg(t).to_u64
    v = a * b
    @hi = (v >> 32).to_u32
    @lo = (v & 0xFFFFFFFF).to_u32
  end

  def op_xor(instruction)
    d = @d
    s = @s
    t = @t
    v = read_reg(s) ^ read_reg(t)
    set_reg(d, v)
  end

  def op_nor(instruction)
    d = @d
    s = @s
    t = @t
    v = ~(read_reg(s) | read_reg(t))
    set_reg(d, v)
  end

  def op_lh(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    addr = read_reg(s) &+ i
    if addr % 2 == 0
      v = load16(addr).to_i16!
      @load = {t, v.to_u32}
    else
      exception(Exception::LoadAddressError, @current_pc, @delaybool)
    end
  end

  def op_sllv(instruction)
    d = @d
    s = @s
    t = @t
    v = read_reg(t) << (read_reg(s) & 0x1F)
    set_reg(d, v)
  end

  def op_lhu(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    addr = read_reg(s) &+ i
    if addr % 2 == 0
      v = load16(addr)
      @load = {t, v.to_u32}
    else
      exception(Exception::LoadAddressError, @current_pc, @delaybool)
    end
  end

  def op_syscall(instruction)
    exception(Exception::SysCall, @current_pc, @delaybool)
  end

  def op_mthi(instruction)
    s = @s
    @hi = read_reg(s)
  end

  def op_mtlo(instruction)
    s = @s
    @lo = read_reg(s)
  end

  def op_slt(instruction)
    d = @d
    s = @s
    t = @t
    s = read_reg(s).to_i32!
    t = read_reg(t).to_i32!
    v = s < t ? 1_u32 : 0_u32
    set_reg(d, v)
  end

  def op_mfhi(instruction)
    d = @d
    hi = @hi
    set_reg(d, hi)
  end

  def op_divu(instruction)
    s = @s
    t = @t
    n = read_reg(s)
    d = read_reg(t)
    if d == 0
      @hi = n
      @lo = 0xFFFFFFFF
    else
      @hi = n % d
      @lo = n // d
    end
  end

  def op_sltiu(instruction)
    i = imm_se(instruction)
    s = @s
    t = @t
    v = read_reg(s) < i ? 1_u32 : 0_u32 # when 0, 1 Janky hack m8, that should be the opposite but it works??????+
    set_reg(t, v)
  end

  def op_srl(instruction)
    i = @shift
    t = @t
    d = @d
    v = read_reg(t) >> i
    set_reg(d, v)
  end

  def op_mflo(instruction)
    d = @d
    lo = @lo
    set_reg(d, lo)
  end

  def op_div(instruction)
    s = @s
    t = @t
    n = read_reg(s).to_i32!
    d = read_reg(t).to_i32!
    if d == 0
      @hi = n.to_u32!
      if n >= 0
        @lo = 0xFFFFFFFF
      else
        @lo = 1
      end
    elsif n.to_u32! == 0x80000000 && d == -1
      @hi = 0
      @lo = 0x80000000
    else
      @hi = n.remainder(d).to_u32!
      @lo = (n / d).to_u32!
    end
  end

  def op_sra(instruction)
    i = @shift
    t = @t
    d = @d
    v = read_reg(t).to_i32!
    v >>= i
    set_reg(d, v.to_u32!)
  end

  def op_subu(instruction)
    s = @s
    t = @t
    d = @d
    v = read_reg(s) &- read_reg(t)
    set_reg(d, v)
  end

  def op_slti(instruction)
    i = imm_se(instruction).to_i32!
    s = @s
    t = @t
    v = read_reg(s).to_i32!
    v = v < i ? 1_u32 : 0_u32
    set_reg(t, v)
  end

  def op_bxx(instruction)
    i = imm_se(instruction)
    s = @s
    is_bgez = (instruction >> 16) & 1
    is_link = (instruction >> 17) & 0xF == 0x8
    v = read_reg(s).to_i32!
    temp = v < 0 ? 1_u32 : 0_u32
    temp = temp ^ is_bgez
    if is_link
      ra = @next_pc
      set_reg(31, ra)
    end
    if temp != 0
      branch(i)
    end
  end

  def op_jalr(instruction)
    d = @d
    s = @s
    ra = @next_pc
    set_reg(d, ra)
    @next_pc = read_reg(s)
    @branchbool = true
  end

  def op_lbu(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    addr = read_reg(s) &+ i
    v = load8(addr)
    @load = {t, v.to_u32}
  end

  def op_blez(instruction)
    i = imm_se(instruction)
    s = @s
    v = read_reg(s).to_i32!
    if v <= 0
      branch(i)
    end
  end

  def op_bgtz(instruction)
    i = imm_se(instruction)
    s = @s
    v = read_reg(s).to_i32!
    if v > 0
      branch(i)
    end
  end

  def op_add(instruction)
    s = @s
    t = @t
    d = @d
    s = read_reg(s).to_i32!
    t = read_reg(t).to_i32!
    begin
      v = s + t
      set_reg(d, (s &+ t).to_u32!)
    rescue ex
      exception(Exception::Overflow, @current_pc, @delaybool)
    end
  end

  def op_and(instruction)
    d = @d
    s = @s
    t = @t
    v = read_reg(s) & read_reg(t)
    set_reg(d, v)
  end

  def op_beq(instruction)
    i = imm_se(instruction)
    s = @s
    t = @t
    if read_reg(s) == read_reg(t)
      branch(i)
    end
  end

  def op_lb(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    addr = read_reg(s) &+ i
    v = load8(addr).to_i8!
    @load = {t, v.to_u32!}
  end

  def op_jr(instruction)
    s = @s
    @next_pc = read_reg(s)
    @branchbool = true
  end

  def op_sb(instruction)
    if @cop0.cache_isolated
      #puts "Ignoring store while cache is isolated"
    else
      i = imm_se(instruction)
      t = @t
      s = @s
      addr = read_reg(s) &+ i
      v = read_reg(t) & 0xFF
      store8(addr, v.to_u8)
    end
  end

  def op_andi(instruction)
    i = @imm
    t = @t
    s = @s
    v = read_reg(s) & i
    set_reg(t, v)
  end

  def op_jal(instruction)
    ra = @next_pc
    set_reg(31, ra)
    op_j(instruction)
    @branchbool = true
  end

  def op_sh(instruction)
    if @cop0.cache_isolated
      #puts "Ignoring store while cache is isolated"
    else
      i = imm_se(instruction)
      t = @t
      s = @s
      addr = read_reg(s) &+ i
      if addr % 2 == 0
        v = read_reg(t) & 0xFFFF
        store16(addr, v.to_u16)
      else
        exception(Exception::StoreAddressError, @current_pc, @delaybool)
      end
    end
  end

  def op_sltu(instruction)
    d = @d
    s = @s
    t = @t
    v = read_reg(s) < read_reg(t) ? 1_u32 : 0_u32
    set_reg(d, v)
  end

  def op_addu(instruction)
    s = @s
    t = @t
    d = @d
    v = read_reg(s) &+ read_reg(t)
    set_reg(d, v)
  end

  def op_lw(instruction)
    if @cop0.cache_isolated
      puts "Ignoring load while cache is isolated"
    else
      i = imm_se(instruction)
      t = @t
      s = @s
      addr = read_reg(s) &+ i
      if addr % 4 == 0
        v = load32(addr)
        @load = {t, v}
      else
        exception(Exception::LoadAddressError, @current_pc, @delaybool)
      end
    end
  end

  def op_addi(instruction)
    i = imm_se(instruction)
    i = (i ^ 0x80000000) &- 0x80000000
    i = i.to_u64
    t = @t
    s = @s
    s = read_reg(s).to_u64
    v = s + i
    if ((v ^ s) & (v ^ i)) & 0x80000000 != 0
      exception(Exception::Overflow, @current_pc, @delaybool)
    else
      v &= 0xFFFFFFFF
      set_reg(t, v.to_u32)
    end
  end


  def op_bne(instruction)
    i = imm_se(instruction)
    s = @s
    t = @t
    if read_reg(s) != read_reg(t)
      branch(i)
    end
  end

  def op_cop0(instruction)
    case @s
    when 0b00000 then op_mfc0
    when 0b00100 then op_mtc0
    when 0b10000 then @cop0.return_from_exception
    else
      raise "unhandled cop0 instruction 0x#{instruction.to_s(16)}, #{@s.to_s(2)}"
    end
  end

  def op_mfc0
    cpu_r = @t
    cop_r = @d
    case cop_r
    when 6, 7, 8 then v = 0_u32 # random jumps, DCIC, exception writes
    when 12 then v = @cop0.sr
    when 13 then v = @cop0.cause
    when 14 then v = @cop0.epc
    when 15 then v = PROCESSOR_ID
    else
      raise "Unhandled read from cop0r #{cop_r}"
    end
    @load = {cpu_r, v}
  end

  def op_mtc0
    cpu_r = @t
    cop_r = @d
    v = read_reg(cpu_r)
    case cop_r
    when 3, 5, 6, 7, 9, 11
      if v != 0
        raise "Unhandled write to cop0r #{cop_r}"
      end
    when 12 then @cop0.set_sr(v)
    when 13 then @cop0.set_cause(v)
    else
      raise "Unhandled cop0 register #{cop_r}"
    end
  end

  def op_or(instruction)
    d = @d
    s = @s
    t = @t
    v = read_reg(s) | read_reg(t)
    set_reg(d, v)
  end

  def op_j(instruction)
    i = imm_jump(instruction)
    @next_pc = (@pc & 0xF0000000) | (i << 2)
    @branchbool = true
  end

  def op_addiu(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    v = read_reg(s) &+ i
    set_reg(t, v)
  end

  def op_lui(instruction)
    i = @imm
    t = @t
    v = i << 16
    set_reg(t, v)
  end

  def op_ori(instruction)
    i = @imm
    t = @t
    s = @s

    v = read_reg(s) | i
    set_reg(t, v)
  end

  def op_sw(instruction)
    i = imm_se(instruction)
    t = @t
    s = @s
    addr = read_reg(s) &+ i
    v = read_reg(t)
    if addr % 4 == 0
      store32(addr, v)
    else
      exception(Exception::StoreAddressError, @current_pc, @delaybool)
    end
  end

  def op_sll(instruction)
    i = @shift
    t = @t
    d = @d
    v = read_reg(t) << i
    set_reg(d, v)
  end
end
