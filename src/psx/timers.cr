struct Timer
  def initialize
    @counter = 0_u16
    @target = 0_u16
    @use_sync = false
    @sync = Sync.from_field(0)
    @target_wrap = false
    @target_irq = false
    @wrap_irq = false
    @repeat_irq = false
    @negate_irq = false
    @clock_source = ClockSource.from_field(0)
    @target_reached = false
    @overflow_reached = false
    @period = FracCycles.from_cycles(1)
    @phase = FracCycles.from_cycles(0)
    @interrupt = false
  end

  def reconfigure
    
  end
end

struct Timers
  def initialize
    @timers = Array.new(3, Timer.new)
  end
end
