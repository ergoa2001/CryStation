require "./psx/bus"
require "./psx/cpu"

# TODO: Write documentation for `Psx`
module Psx
  VERSION = "0.1.0"
  extend self

  def run
    puts "running"
    bus = Bus.new
    cpu = CPU.new(bus)
    while true
      cpu.run_next_instruction
    end
  end
end

Psx.run
