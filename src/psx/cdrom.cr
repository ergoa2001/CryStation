class Fifo
  @buffer : Array(UInt8)
  def initialize
    @buffer = Array.new(16, 0_u8)
    @write_idx = 0_u8
    @read_idx = 0_u8
  end

  def is_empty : Bool
    @write_idx == @read_idx
  end

  def is_full : Bool
    @write_idx == @read_idx ^ 0x10
  end

  def clear
    @write_idx = 0_u8
    @read_idx = 0_u8
    @buffer = Array.new(16, 0_u8)
  end

  def len : UInt8
    (@write_idx &- @read_idx) & 0x1F
  end

  def push(val : UInt8)
    idx = (@write_idx & 0xF_u8)
    @buffer[idx] = val
    @write_idx = (@write_idx &+ 1) & 0x1F
  end

  def pop : UInt8
    idx = (@read_idx & 0xF_u8)
    @read_idx = (@read_idx &+ 1) & 0x1F
    @buffer[idx]
  end
end

class CdRom
  def initialize(irq : InterruptState)
    @responses = Fifo.new
    @parameters = Fifo.new
    @index = 0_u8
    @irq_flags = 0_u8
    @irq_mask = 0_u8
    @irq_state = irq
    @seek_target = 0
  end

  def irq_ack(val : UInt8)
    @irq_flags &= ~val
  end

  def set_interrupt_mask(val : UInt8)
    @irq_mask = val & 0x1F
  end

  def status : UInt8
    r = @index
    r |= 0_u8 << 2
    r |= @parameters.is_empty ? 1_u8 << 3 : 0_u8 << 3
    r |= @parameters.is_full ? 0_u8 << 4 : 1_u8 << 4
    r |= @responses.is_empty ? 0_u8 << 5 : 1_u8 << 5
    r
  end

  def set_parameter(val : UInt8)
    if @parameters.is_full
      raise "CDROM: Parameter FIFO overflow!"
    end
    @parameters.push(val)
  end

  def run_command(val : UInt8)
    case val
    when 0x01 then cmd_get_stat
    when 0x02 then cmd_set_loc
    when 0x0A then cmd_init
    when 0x0E then cmd_set_mode
    when 0x15 then cmd_seek_l
    when 0x19 then cmd_test
    else puts "CDROM: Unhandled CDROM command 0x#{val.to_s(16)}"
    end
  end

  def cmd_set_mode
    mode = @parameters.pop
    status = 0x10_u8 #drive_status
    @responses.push(status)
    trigger_irq(3_u8, 25000)
  end

  def cmd_seek_l
    #do_seek
    status = 0x10_u8 #drive_status
    @responses.push(status)
    trigger_irq(3_u8, 25000)
    trigger_irq(2_u8, 50000)
  end

  def cmd_set_loc
    m = @parameters.pop
    s = @parameters.pop
    f = @parameters.pop
    status = 0x10_u8 # drive_status
    @responses.push(status)
    trigger_irq(3_u8, 25000)
  end

  def cmd_init
    status = 0x10_u8 #drive_status
    @responses.push(status)
    trigger_irq(3_u8, 25000)
    trigger_irq(2_u8, 50000)
  end

  def irq : Bool
    @irq_flags & @irq_mask != 0
  end

  def trigger_irq(irqval : UInt8, delay)
    @irq_flags = irqval
    if irq
      @irq_state.pend_irq(delay, Interrupt::CdRom)
    end
  end

  def get_bios_date
    @responses.push(0x98)
    @responses.push(0x06)
    @responses.push(0x10)
    @responses.push(0xC3)
    trigger_irq(3_u8, 25000)
  end

  def cmd_get_stat
    status = 0x10_u8 #drive_status
    @responses.push(status)
    trigger_irq(3_u8, 25000)
  end

  def cmd_test
    sub_command = @parameters.pop
    case sub_command
    when 0x20 then get_bios_date
    else puts "CDROM: Unhandled test command 0x#{sub_command.to_s(16)}"
    end
  end

  def load8(offset : UInt32) : UInt8
    index = @index
    case offset
    when 0 then status
    when 1
      if @responses.is_empty
        raise "CDROM: Response FIFO underflow!"
      end
      @responses.pop
    when 3
      case index
      when 1 then @irq_flags | 0xE0
      else
        puts "CDROM: Unhandled load8  #{offset}.#{@index}"
        0x00_u8
      end
    else
      puts "CDROM: Unhandled load8  #{offset}.#{@index}"
      0x00_u8
    end
  end

  def store8(offset : UInt32, val : UInt8)
    index = @index
    case offset
    when 0 then @index = val & 3
    when 1
      case index
      when 0 then run_command(val)
      else puts "CDROM: Unhandled store8 #{offset}.#{index}, value 0x#{val.to_s(16)}"
      end
    when 2
      case index
      when 0 then set_parameter(val)
      when 1 then set_interrupt_mask(val)
      else puts "CDROM: Unhandled store8 #{offset}.#{index}, value 0x#{val.to_s(16)}"
      end
    when 3
      case index
      when 1
        irq_ack(val & 0x1F)
        if val & 0x40 != 0
          @parameters.clear
        end
      else puts "CDROM: Unhandled store8 #{offset}.#{index}, value 0x#{val.to_s(16)}"
      end
    else puts "CDROM: Unhandled store8 #{offset}.#{index}, value 0x#{val.to_s(16)}"
    end
  end
end
