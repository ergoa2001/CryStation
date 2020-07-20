enum Interrupt
  VBlank = 0
  CdRom = 2
  Dma = 3
  Timer0 = 4
  Timer1 = 6
  Timer2 = 6
  PadMemCard = 7
end


class InterruptState
  def initialize
    @status = 0_u16
    @mask = 0_u16
    @pending_irqs = Array(Tuple(Int32, Interrupt)).new
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

  def assert(which)
    @status |= 1 << (which.value)
  end

  def pend_irq(delay, which)
    @pending_irqs << {delay, which}
  end

  def tick
    start_size = @pending_irqs.size
    deleted_items = 0
    if start_size != 0
      (0...start_size).each do |i|
        which = @pending_irqs[i - deleted_items][1]
        delay = @pending_irqs[i - deleted_items][0]
        delay -= 1
        if delay == 0
          assert(which)
          @pending_irqs.delete_at(i - deleted_items)
          deleted_items += 1
        else
          @pending_irqs[i - deleted_items] = {delay, which}
        end
      end
    end
  end
end
