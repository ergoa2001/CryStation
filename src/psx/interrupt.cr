struct InterruptState
  enum Interrupt
    VBlank = 0
    CdRom = 2
    Dma = 3
    Timer0 = 4
    Timer1 = 6
    Timer2 = 6
    PadMemCard = 7
  end

  def initialize
    @status = 0_u16
    @mask = 0_u16
  end

  def active : Bool
    (@status & @mask) != 0
  end

  def status  : UInt16
    @status
  end

  def ack(ack : UInt16)
    @status &= ack
  end

  def mask : UInt16
    @mask
  end

  def set_mask(mask : UInt16)
    @mask = mask
  end

  def asser(which : Interrupt)
    self.status |= 1 << (which.value)
  end

end
