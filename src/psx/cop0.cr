struct Cop0
  enum Exception
    Interrupt = 0x0
    LoadAddressError= 0x4
    StoreAddressError = 0x5
    SysCall = 0x8
    Break = 0x9
    IllegalInstruction = 0xA
    CoprocessorError = 0xB
    Overflow= 0xC
  end

  def initialize(irq : InterruptState)
    @sr = 0_u32
    @cause = 0_u32
    @epc = 0_u32
    @irq = irq
  end

  def sr : UInt32
    @sr
  end

  def set_sr(sr : UInt32)
    @sr = sr
  end

  def set_cause(v : UInt32)
    @cause &= ~0x300
    @cause |= v & 0x300
  end

  def cause : UInt32
    active = @irq.active ? 1_u32 : 0_u32
    @cause | (active << 10)
  end

  def epc : UInt32
    @epc
  end

  def cache_isolated : Bool
    @sr & 0x10000 != 0
  end

  def exception(cause, pc : UInt32, in_delay_slot : Bool) : UInt32
    mode = @sr & 0x3F
    @sr &= ~0x3F
    @sr |= (mode << 2) & 0x3F
    @cause &= ~0x7C
    @cause = cause.value << 2
    if in_delay_slot
      @epc = @epc &- 4
      @cause |= 1 << 31
    else
      @epc = pc
      @cause &= ~(1 << 31)
    end
    case @sr & (1 << 22) != 0
    when true then 0xBFC00180_u32
    else 0x80000080_u32
    end
  end

  def return_from_exception
    mode = @sr & 0x3F
    @sr &= ~0xF
    @sr |= mode >> 2
  end

  def irq_enabled : Bool
    @sr & 1 != 0
  end

  def irq_active : Bool
    cause = @cause
    pending = (cause & @sr) & 0x700
    irq_enabled && pending != 0
  end

end
