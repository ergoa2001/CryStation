class Bios
  BIOS_SIZE = 512*1024
  @data : Array(UInt8)

  def initialize
    @data = Array.new BIOS_SIZE, 0_u8
    file = File.read("./src/psx/SCPH1001.BIN").bytes
    if file.size == BIOS_SIZE
      puts "BIOS OK!"
      @data = file
    else
      raise "Invalid BIOS size"
    end
  end

  def load32(offset : UInt32) : UInt32
    b0 = @data[offset + 0].to_u32
    b1 = @data[offset + 1].to_u32
    b2 = @data[offset + 2].to_u32
    b3 = @data[offset + 3].to_u32

    b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
  end

  def load8(offset : UInt32) : UInt8
    @data[offset]
  end
end
