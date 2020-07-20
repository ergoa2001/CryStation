class Ram
  @data : Array(UInt8)
  def initialize
    @data = Array.new 2*1024*1024, 0xCA_u8
    @pc = 0_u32
    end

  def sideload(file)
    puts "Sideloading #{file}"
    file_content = File.read(file)
    File.open(file) do |io|
      magic = io.gets(8)
      if magic != "PS-X EXE"
        raise "Invalid PSEXE file"
      end
      io.gets(4)
      io.gets(4)
      @pc = UInt32.from_io(io, IO::ByteFormat::LittleEndian)
      io.gets(4)
      addr = UInt32.from_io(io, IO::ByteFormat::LittleEndian)
      regionmask = [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0x7FFFFFFF, 0x1FFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]
      index = addr >> 29
      addr &= regionmask[index]
      size = UInt32.from_io(io, IO::ByteFormat::LittleEndian)
      io.gets(2016)
      newaddr = addr
      newsize = size
      while newsize > 0
        data = Slice(UInt8).new(newsize)
        bytes_read = io.read(data)
        data = data[0, bytes_read].to_a
        newsize -= data.size
        @data[newaddr..data.size] = data
        newaddr = addr + bytes_read
      end
      puts "Magic: #{magic}"
      puts "New PC: 0x#{@pc.to_s(16)}"
      puts "Ram write address?: 0x#{addr.to_s(16)}"
      puts "Loaded file size: #{size} bytes"
      puts "Sideloading #{file} done!"
    end
  end

  def pc
    @pc
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

class ScratchPad
  @data : Array(UInt8)
  def initialize
    @data = Array.new(1024, 0xdb_u8)
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
