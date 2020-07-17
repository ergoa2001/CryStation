struct Counter
  def initialize
    @count = 0_u32
  end

  def reset
    @count = 0
  end

  def increment
    @count &+= 1
  end

  def get : UInt32
    @count
  end
end

struct Counters
  def initialize
    # Incremented every time a new frame is drawn
    @frame = Counter.new
    # Incremented on display area set
    @framebuffer_swap = Counter.new
    # Incremented when a cpu interrupt is active
    @cpu_interrupt = Counter.new
  end

  def frame
    @frame
  end

  def cpu_interrupt
    @cpu_interrupt
  end
end
