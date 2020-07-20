class Timer
  def initialize
    @counter = 0_u16
    @target = 0_u16
    @wrap_irq = false
    @use_sync = false
    @sync = 0_u16
    @target_wrap = false
    @target_irq = false
    @repeat_irq = false
    @negate_irq = false
    @clock_source = 0_u16
    @interrupt = false
    @target_reached = false
    @overflow_reached = false
  end

  def counter
    @counter
  end

  def target
    @target
  end

  def mode : UInt16
    r = 0_u16
    r |= @use_sync ? 1_u16 : 0_u16
    r |= @sync << 1
    r |= @target_wrap ? 1_u16 << 3 : 0_u16 << 3
    r |= @target_irq ? 1_u16 << 4 : 0_u16 << 4
    r |= @wrap_irq ? 1_u16 << 5 : 0_u16 << 5
    r |= @repeat_irq ? 1_u16 << 6 : 0_u16 << 6
    r |= @negate_irq ? 1_u16 << 7 : 0_u16 << 7
    r |= @clock_source << 8
    r |= @interrupt ? 0_u16 << 10 : 1_u16 << 10
    r |= @target_reached ? 1_u16 << 11 : 0_u16 << 11
    r |= @overflow_reached ? 1_u16 << 12 : 0_u16 << 12
    @target_reached = false
    @overflow_reached = false
    r
  end

  def set_target(val : UInt16)
    @target = val
  end

  def set_mode(val : UInt16)
    @use_sync = (val & 1) != 0
    @sync = (val >> 1) & 3
    @target_wrap = (val >> 3) & 1 != 0
    @target_irq = (val >> 4) & 1 != 0
    @wrap_irq = (val >> 5) & 1 != 0
    @repeat_irq = (val >> 6) & 1 != 0
    @negate_irq = (val >> 7) & 1 != 0
    @clock_source = (val >> 8) & 1
    @interrupt = false
    @counter = 0
  end

  def set_counter(val : UInt16)
    @counter = val
  end

  def tick_counter
    @counter += 1
  end

  def wrap_irq : Bool
    @wrap_irq
  end

  def set_target_reached(val : Bool)
    @target_reached = val
  end

  def set_overflow_reached(val : Bool)
    @overflow_reached = val
  end

  def target_wrap : Bool
    @target_wrap
  end

  def target_irq : Bool
    @target_irq
  end

  def negate_irq : Bool
    @negate_irq
  end

  def set_interrupt(val : Bool)
    @interrupt = val
  end

end

class Timers
  @timers : Array(Timer)
  def initialize(irq : InterruptState)
    @irq_state = irq
    @timers = Array.new(3, Timer.new)
  end

  def store16(offset : UInt32, val : UInt16 | UInt32)
    val = val.to_u16!
    instance = offset >> 4
    case offset & 0xF
    when 0
      puts "COUNTER: Setting counter to #{val} on timer #{instance}"
      @timers[instance].set_counter(val)
    when 4
      puts "COUNTER: Setting mode to #{val} on timer #{instance}"
      @timers[instance].set_mode(val)
    when 8
      puts "COUNTER: Setting target to #{val} on timer #{instance}"
      @timers[instance].set_target(val)
    else raise "Unhandled timer register #{offset & 0xF}"
    end
  end

  def load32(offset : UInt32) : UInt32
    instance = offset >> 4
    case offset & 0xF
    when 0 then @timers[instance].counter.to_u32
    when 4 then @timers[instance].mode.to_u32
    when 8 then @timers[instance].target.to_u32
    else raise "Unhandled timer register #{offset & 0xF}"
    end
  end

  def tick
    count = @timers[2].counter.to_u32 + 1
    target_passed = false
    if @timers[2].counter <= @timers[2].target && count > @timers[2].target
      @timers[2].set_target_reached(true)
      target_passed = true
    end
    if @timers[2].target_wrap
      wrap = @timers[2].target.to_u32 + 1
    else
      wrap = 0x10000
    end

    if count >= wrap
      count = count.remainder(wrap)
      if wrap = 0x10000
        @timers[2].set_overflow_reached(true)
        overflow = true
      end
    end

    @timers[2].set_counter(count.to_u16!)
    if (@timers[2].wrap_irq && overflow) || (@timers[2].target_irq && target_passed)
      @irq_state.assert(Interrupt::Timer2)
      if @timers[2].negate_irq
        raise "Unhandled negate irq"
      else
        @timers[2].set_interrupt(true)
      end
    elsif @timers[2].negate_irq == false
      @timers[2].set_interrupt(false)
    end

  end
end
