class DmaChannel
  enum Direction : UInt32
    ToRam
    FromRam
  end

  enum Step : UInt32
    Increment
    Decrement
  end

  enum Sync : UInt32
    Manual
    Request
    LinkedList
  end

  def initialize
    @enable = false
    @direction = Direction::ToRam
    @step = Step::Increment
    @sync = Sync::Manual
    @trigger = false
    @chop = false
    @chop_dma_sz = 0_u8
    @chop_cpu_sz = 0_u8
    @dummy = 0_u8
    @base = 0_u32
    @block_size = 0_u16
    @block_count = 0_u16
  end

  def done
    @enable = false
    @trigger = false
  end

  def transfer_size
    bs = @block_size.to_u32
    bc = @block_count.to_u32
    if @sync == Sync::Manual
      bs
    else
       bc*bs
    end
  end

  def direction
    @direction
  end

  def step
    @step
  end

  def active : Bool
    trigger = case @sync
    when Sync::Manual then @trigger
    else true
    end
    @enable && trigger
  end

  def set_block_control(val : UInt32)
    @block_size = val.to_u16!
    @block_count = (val >> 16).to_u16
  end

  def block_control : UInt32
    bs = @block_size.to_u32
    bc = @block_count.to_u32
    (bc << 16) | bs
  end

  def set_base(val : UInt32)
    @base = val & 0xFFFFFF
  end

  def base : UInt32
    @base
  end

  def set_control(val : UInt32)
    case val & 1 != 0
    when true then @direction = Direction::FromRam
    when false then @direction = Direction::ToRam
    end
    case (val >> 1) & 1 != 0
    when true then @step = Step::Decrement
    when false then @step = Step::Increment
    end
    @chop = (val >> 8) & 1 != 0
    @sync = case (val >> 9) & 3
    when 0 then Sync::Manual
    when 1 then Sync::Request
    when 2 then Sync::LinkedList
    else raise "Unknown DMA sync mode #{(val >> 9) & 3}"
    end
    @chop_dma_sz = ((val >> 16) & 7).to_u8
    @chop_cpu_sz = ((val >> 20) & 7).to_u8
    @enable = (val >> 24) & 1 != 0
    @trigger = (val >> 28) & 1 != 0
    @dummy = ((val >> 29) & 3).to_u8
  end

  def control : UInt32
    r = 0_u32
    r |= @direction.value << 0
    r |= @step.value << 1
    r |= @chop ? 1_u32 << 8 : 0_u32 << 8
    r |= @sync.value << 9
    r |= @chop_dma_sz.to_u32 << 16
    r |= @chop_cpu_sz.to_u32 << 20
    r |= @enable ? 1_u32  << 24 : 0_u32 << 24
    r |= @trigger ? 1_u32 << 28 : 0_u32 << 28
    r |= @dummy.to_u32 << 29
  end

  def sync
    @sync
  end
end

class Dma
  enum Port
    MdecIn
    MdecOut
    Gpu
    CdRom
    Spu
    Pio
    Otc
  end

  def from_index(index : UInt32) : Port
    case index
    when 0 then Port::MdecIn
    when 1 then Port::MdecOut
    when 2 then Port::Gpu
    when 3 then Port::CdRom
    when 4 then Port::Spu
    when 5 then Port::Pio
    when 6 then Port::Otc
    else raise "Invalid port #{index}"
    end
  end

  def initialize
    @control = 0x07854321_u32
    @irq_en = false
    @channel_irq_en = 0_u8
    @channel_irq_flags = 0_u8
    @force_irq = false
    @irq_dummy = 0_u8
    @channels = [DmaChannel.new, DmaChannel.new, DmaChannel.new, DmaChannel.new, DmaChannel.new, DmaChannel.new, DmaChannel.new]
  end

  def channel(port : Port | Nil)
    if port == Nil
      raise "no port"
    else
      @channels[port.value]
    end
  end

  def irq : Bool
    channel_irq = @channel_irq_flags & @channel_irq_en

    @force_irq || (@irq_en && channel_irq != 0)
  end

  def interrupt : UInt32
    r = 0_u32
    r |= @irq_dummy.to_u32
    r |= @force_irq ? 1_u32 << 15 : 0_u32 << 15
    r |= @channel_irq_en.to_u32 << 15
    r |= @irq_en ? 1_u32 << 16 : 0_u32 << 16
    r |= @channel_irq_flags.to_u32 << 24
    r |= irq ? 1_u32 << 31 : 0_u32 << 31
  end

  def set_interrupt(val : UInt32)
    @irq_dummy = (val & 0x3F).to_u8
    @force_irq = (val >> 15) & 1 != 0
    @channel_irq_en = ((val >> 16) & 0x7F).to_u8
    @irq_en = (val >> 23) & 1 != 0
    ack = ((val >> 24) & 0x3F).to_u8
    @channel_irq_flags &= ~ack
  end

  def control : UInt32
    @control
  end

  def set_control(val : UInt32)
    @control = val
  end
end
