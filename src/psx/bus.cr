require "./bios"
require "./ram"
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
  CDROM_RANGE = {0x1f801800, 0x4}

  def initialize
    @bios = Bios.new
    @ram = Ram.new
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
      puts "DMA read 0x#{addr_abs.to_s(16)}"
      0x00_u32
    elsif offset = contains(addr_abs, GPU_RANGE)
      puts "GPU read 0x#{offset.to_s(16)}"
      case offset
      when 4 then 0x10000000_u32
      else
        0x00_u32
      end
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
    elsif offset = contains(addr_abs, CDROM_RANGE)
      puts "CDROM LOAD, 0x#{addr_abs.to_s(16)}"
      0xFF_u8
    else
      raise "unhandled load8 at address 0x#{addr_abs.to_s(16)}"
    end
  end

  def store32(addr : UInt32, val : UInt32)
    addr_abs = mask_region(addr)
    if addr % 4 != 0
      raise "Unaligned store32 address: #{addr.to_s(16)}"
    end
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
      puts "DMA write 0x#{addr_abs.to_s(16)}, 0x#{val.to_s(16)}"
    elsif offset = contains(addr_abs, GPU_RANGE)
      puts "GPU write #{offset}, 0x#{val.to_s(16)}"
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
    elsif offset = contains(addr_abs, CDROM_RANGE)
      puts "CDROM, 0x#{addr_abs.to_s(16)}"
    else
      raise "unhandled store8 into address 0x#{addr.to_s(16)}"
    end
  end
end
