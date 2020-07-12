require "./bios"
require "./ram"
require "./dma"
require "./gpu"

class Bus
  REGION_MASK = [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0x7FFFFFFF, 0x1FFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]

  BIOS_RANGE = {0x1FC00000, 512*1024}
  MEMCONTROL_RANGE = {0x1F801000, 36}
  RAMSIZE_RANGE = {0x1F801060, 4}
  CACHECONTROL_RANGE = {0xFFFE0130, 4}
  RAM_RANGE = {0x00000000, 2*1024*1024}
  SPU_RANGE = {0x1F801C00, 640}
  EXPANSION2_RANGE = {0x1F802000, 66}
  EXPANSION1_RANGE = {0x1F000000, 512*1024}
  IRQCONTROL_RANGE = {0x1F801070, 8}
  TIMERS_RANGE = {0x1F801100, 0x30}
  DMA_RANGE = {0x1F801080, 0x80}
  GPU_RANGE = {0x1F801810, 8}
  #CDROM_RANGE = {0x1f801800, 0x4}

  def initialize
    @bios = Bios.new
    @ram = Ram.new
    @dma = Dma.new
    @gpu = Gpu.new
  end

  def do_dma_linked_list(port)
    channel = @dma.channel(port)
    addr = channel.base & 0x1FFFFC
    if channel.direction.value == 0
      raise "Invalid DMA direction for linked list mode"
    end
    if port.value != 2
      raise "Attempted linked list DMA on port #{port}"
    end
    running = true
    while running
      header = @ram.load32(addr)
      remsz = header >> 24
      while remsz > 0
        addr = (addr + 4) & 0x1FFFFC
        command = @ram.load32(addr)
        @gpu.gp0(command)
        remsz -= 1
      end
      if header & 0x800000 != 0
        running = false
      end
      addr = header & 0x1FFFFC
    end
    channel.done
  end

  def do_dma_block(port)
    channel = @dma.channel(port)
    if channel.step.value == 0
      increment = 4
    else
      increment = -4
    end
    addr = channel.base
    remsz = channel.transfer_size
    while remsz > 0
      cur_addr = addr & 0x1FFFFC
      case channel.direction.value
      #To Ram
      when 0
        src_word = case port.value
        when 6
          case remsz
          when 1 then 0xFFFFFF_u32
          else (addr &- 4) & 0x1FFFFFF
          end
        else
          raise "Unhandled DMA source port #{port}"
        end
        @ram.store32(cur_addr, src_word)
      #From Ram
      when 1
        src_word = @ram.load32(cur_addr)
        case port.value
        when 2 then @gpu.gp0(src_word)
        else
          raise "Unhandled DMA destination port #{port}"
        end
      end
      addr = addr &+ increment
      remsz -= 1
    end
    channel.done
  end

  def do_dma(port)
    case @dma.channel(port).sync.value
    when 2 then do_dma_linked_list(port)
    else do_dma_block(port)
    end
  end

  def set_dma_reg(offset : UInt32, val : UInt32)
    major = (offset & 0x70) >> 4
    minor = offset & 0xF
    case major
    when 0..6
      port = @dma.from_index(major)
      channel = @dma.channel(port)
      case minor
      when 0 then channel.set_base(val)
      when 4 then channel.set_block_control(val)
      when 8 then channel.set_control(val)
      else raise "Unhandled DMA write 0x#{offset.to_s(16)}, 0x#{val.to_s(16)}"
      end
      if channel.active
        do_dma(port)
      end
    when 7
      case minor
      when 0 then @dma.set_control(val)
      when 4 then @dma.set_interrupt(val)
      else raise "Unhandled DMA write 0x#{offset.to_s(16)}, 0x#{val.to_s(16)}"
      end
    else raise "Unhandled DMA write 0x#{offset.to_s(16)}, 0x#{val.to_s(16)}"
    end
  end

  def dma_reg(offset : UInt32) : UInt32
    major = (offset & 0x70) >> 4
    minor = offset & 0xF
    case major
    when 0..6
      channel = @dma.channel(@dma.from_index(major))
      case minor
      when 0 then channel.base
      when 4 then channel.block_control
      when 8 then channel.control
      else raise "Unhandled DMA read at 0x#{offset.to_s(16)}"
      end
    when 7
      case minor
      when 0 then @dma.control
      when 4 then @dma.interrupt
      else raise "Unhandled DMA read at 0x#{offset.to_s(16)}"
      end
    else raise "Unhandled DMA read at 0x#{offset.to_s(16)}"
    end
  end

  def contains(addr : UInt32, range) : Nil | UInt32
    if addr >= range[0] && addr < (range[0] + range[1])
      addr - range[0]
    end
  end

  def mask_region(addr : UInt32) : UInt32
    index = addr >> 29
    addr & REGION_MASK[index]
  end

  def load32(addr : UInt32) : UInt32
    addr_abs = mask_region(addr)
    if addr % 4 != 0
      raise "Unaligned load32 address: #{addr.to_s(16)}"
    end

    if offset = contains(addr_abs, BIOS_RANGE)
      @bios.load32(offset)
    elsif offset = contains(addr_abs, RAM_RANGE)
      @ram.load32(offset)
    elsif offset = contains(addr_abs, IRQCONTROL_RANGE)
      puts "IRQCONTROL read 0x#{offset.to_s(16)}"
      0x00_u32
    elsif offset = contains(addr_abs, DMA_RANGE)
      dma_reg(offset)
    elsif offset = contains(addr_abs, GPU_RANGE)
      case offset
      when 0 then @gpu.read
      when 4 then 0x1C000000_u32
      else
        0x00_u32
      end
    elsif offset = contains(addr_abs, TIMERS_RANGE)
      0x00_u32
    else
      raise "unhandled fetch32 at address #{addr.to_s(16)}"
    end
  end

  def load16(addr : UInt32) : UInt16
    addr_abs = mask_region(addr)
    if offset = contains(addr_abs, SPU_RANGE)
      puts "Unhandled read from SPU register 0x#{addr_abs.to_s(16)}"
      0x00_u16
    elsif offset = contains(addr_abs, RAM_RANGE)
      @ram.load16(offset)
    elsif offset = contains(addr_abs, IRQCONTROL_RANGE)
      puts "IRQ control read offset"
      0x00_u16
    else
      raise "unhandled load16 at address 0x#{addr.to_s(16)}"
    end
  end

  def load8(addr : UInt32) : UInt8
    addr_abs = mask_region(addr)
    if offset = contains(addr_abs, BIOS_RANGE)
      @bios.load8(offset)
    elsif offset = contains(addr_abs, EXPANSION1_RANGE)
      0xFF_u8
    elsif offset = contains(addr_abs, RAM_RANGE)
      @ram.load8(offset)
    else
      raise "unhandled load8 at address 0x#{addr_abs.to_s(16)}"
    end
  end

  def store32(addr : UInt32, val : UInt32)
    addr_abs = mask_region(addr)
    if offset = contains(addr_abs, MEMCONTROL_RANGE)
      case offset
      when 0
        if val != 0x1F000000
          raise "Bad expansion 1 base address #{val.to_s(16)}"
        end
      when 4
        if val != 0x1F802000
          raise "Bad expansion 2 base address #{val.to_s(16)}"
        end
      else
        puts "Unhandled write to MEMCONTROL register"
      end
    elsif offset = contains(addr_abs, RAMSIZE_RANGE)
      puts "RAMSIZE write"
    elsif offset = contains(addr_abs, RAM_RANGE)
      @ram.store32(offset, val)
    elsif offset = contains(addr_abs, CACHECONTROL_RANGE)
      puts "Unhandled CACHECONTROL write"
    elsif offset = contains(addr_abs, IRQCONTROL_RANGE)
      puts "IRQ control write #{offset}, #{val}"
    elsif offset = contains(addr_abs, DMA_RANGE)
      set_dma_reg(offset, val)
    elsif offset = contains(addr_abs, GPU_RANGE)
      case offset
      when 0 then @gpu.gp0(val)
      when 4 then @gpu.gp1(val)
      else raise "GPU write offset 0x#{offset.to_s(16)}, val 0x#{val.to_s(16)}"
      end
    elsif offset = contains(addr_abs, TIMERS_RANGE)
      puts "unhandled write to timer register 0x#{offset.to_s(16)}, 0x#{val.to_s(16)}"
    else
      raise "unhandled store32 into address #{addr_abs.to_s(16)}"
    end
  end

  def store16(addr : UInt32, val : UInt16)
    addr_abs = mask_region(addr)
    if addr % 2 != 0
      raise "Unaligned store16 addr 0x#{addr.to_s(16)}"
    end
    if offset = contains(addr_abs, SPU_RANGE)
      puts "Unhandled write to SPU register 0x#{addr.to_s(16)}"
    elsif offset = contains(addr_abs, TIMERS_RANGE)
      puts "Unhandled write to timer register 0x#{offset.to_s(16)}"
    elsif offset = contains(addr_abs, RAM_RANGE)
      @ram.store16(offset, val)
    elsif offset = contains(addr_abs, IRQCONTROL_RANGE)
      puts "IRQ control write #{offset}, #{val}"
    else
      raise "unhandled store16 into address 0x#{addr_abs.to_s(16)}"
    end
  end

  def store8(addr : UInt32, val : UInt8)
    addr_abs = mask_region(addr)
    if offset = contains(addr_abs, EXPANSION2_RANGE)
      puts("Unhandled write to expansion 2 register 0x#{offset.to_s(16)}")
    elsif offset = contains(addr_abs, RAM_RANGE)
      @ram.store8(offset, val)
    else
      raise "unhandled store8 into address 0x#{addr.to_s(16)}"
    end
  end
end
