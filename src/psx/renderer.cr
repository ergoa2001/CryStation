require "crsfml"

struct Buffer
  @vertex_buffer_len : UInt32
  @memory : Array(UInt16)
  def initialize(datanum : UInt32)
    @datanum = datanum
    @vertex_buffer_len = (64*1024).to_u32
    @memory = Array.new(@vertex_buffer_len, 0_u16)
  end

  def set(index, value)
    (0...@datanum).each do |x|
      @memory[index * @datanum + x] = value[x].to_u16
    end
  end

  def read(index)
    @memory[index]
  end

  def get_array
    @memory
  end
end

class Renderer
  WIDTH  = 1024
  HEIGHT = 512
  VERTEX_BUFFER_LEN = 64*1024

  def initialize
    @nvertices = 0_u32
    @window = SF::RenderWindow.new(SF::VideoMode.new(WIDTH, HEIGHT), "CryStation", settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @positions = Buffer.new(2)
    @colors = Buffer.new(3)
  end

  def push_triangle(positions, colors)
    if @nvertices + 3 > VERTEX_BUFFER_LEN
      puts "Vertex buffer full, drawing"
      draw
    end
    (0...3).each do |i|
      @positions.set(@nvertices, positions[i])
      @colors.set(@nvertices, colors[i])
      @nvertices += 1
    end
  end

  def push_quad(positions, colors)
    if @nvertices + 6 > VERTEX_BUFFER_LEN
      draw
    end
    (0...3).each do |i|
      @positions.set(@nvertices, positions[i])
      @colors.set(@nvertices, colors[i])
      @nvertices += 1
    end
    (1...4).each do |i|
      @positions.set(@nvertices, positions[i])
      @colors.set(@nvertices, colors[i])
      @nvertices += 1
    end
  end

  def draw
    while event = @window.poll_event
      case event
      when SF::Event::Closed
        @window.close
        exit 0
      end
    end
    @window.clear
    (0...@nvertices//3).each do |j|
      triangle = SF::VertexArray.new(SF::Triangles, 3)
      (0...3).each do |i|
        col1 = @colors.read(j*9 + i*3 + 0)
        col2 = @colors.read(j*9 + i*3 + 1)
        col3 = @colors.read(j*9 + i*3 + 2)
        pos1 = @positions.read(j*6 + i*2 + 0)
        pos2 = @positions.read(j*6 + i*2 + 1)
        triangle[i] = SF::Vertex.new(SF.vector2(pos1, pos2), SF.color(col1, col2, col3))
      end
      @window.draw triangle
    end
    @window.display
  end
end
