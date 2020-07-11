class Ram
  @data : Array(UInt8)
  def initialize
    @data = Array.new 2*1024*1024, 0xCA_u8
  end

  def load32(offset : UInt32) : UInt32
    b0 = @data[offset + 0].to_u32
    b1 = @data[offset + 1].to_u32
    b2 = @data[offset + 2].to_u32
    b3 = @data[offset + 3].to_u32
    b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  end

  def load16(offset : UInt32) : UInt16
    b0 = @data[offset + 0].to_u16
    b1 = @data[offset + 1].to_u16
    b0 | (b1 << 8)
  end

  def load8(offset : UInt32) : UInt8
    @data[offset]
  end

  def store32(offset : UInt32, val : UInt32)
    b0 = (val & 0xFF).to_u8
    b1 = ((val >> 8) & 0xFF).to_u8
    b2 = ((val >> 16) & 0xFF).to_u8
    b3 = ((val >> 24) & 0xFF).to_u8
    @data[offset + 0] = b0
    @data[offset + 1] = b1
    @data[offset + 2] = b2
    @data[offset + 3] = b3
  end

  def store16(offset : UInt32, val : UInt16)
    b0 = (val & 0xFF).to_u8
    b1 = ((val >> 8) & 0xFF).to_u8
    @data[offset + 0] = b0
    @data[offset + 1] = b1
  end

  def store8(offset : UInt32, val : UInt8)
    @data[offset] = val
  end
end
