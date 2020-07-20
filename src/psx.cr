require "./psx/bus"
require "./psx/cpu"
require "./psx/interrupt"
require "./psx/counters"
require "./psx/timers"


# TODO: Write documentation for `Psx`
module Psx
  VERSION = "0.1.0"
  extend self

  def run
    puts "running"
    sideload = false
    sideloadfile = "./exes/psxtest_cpu.exe"
    fastboot = false
    counters = Counters.new
    irq = InterruptState.new
    timers = Timers.new(irq)
    bus = Bus.new(irq, counters, timers)
    cpu = CPU.new(bus, irq, counters, timers, sideloadfile, sideload, fastboot)
    frame_time = 0
    while true
      elapsed_time = Time.measure do
        cpu.run_next_instruction
      end
      frame_time += elapsed_time.nanoseconds
      if frame_time >= 1667000*7
        cpu.drawframe
        frame_time = 0
      end
    end
  end
end

Psx.run
