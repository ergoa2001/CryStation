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
  VRAM_SIZE_PIXELS = 1024 * 512
  @vertices : Array(SF::Vertex)
  def initialize
    @nvertices = 0_u32
    @window = SF::RenderWindow.new(SF::VideoMode.new(WIDTH, HEIGHT), "CryStation", settings: SF::ContextSettings.new(depth: 24, antialiasing: 8))
    @window.vertical_sync_enabled = true
    @positions = Buffer.new(2)
    @colors = Buffer.new(3)
    @vram = Array(Array(UInt16)).new(512) { Array.new(1024, 0_u16) }
    @texture = SF::Texture.new(1024, 512)
    @sprite = SF::Sprite.new(@texture)
    @vertices = Array.new(VERTEX_BUFFER_LEN, SF::Vertex.new(SF.vector2(0, 0), SF.color(0, 0, 0)))
    @states = SF::RenderStates.new
    @states.texture = @texture
    @clut_x = 0_u32
    @clut_y = 0_u32
    @page_x = 0_u32
    @page_y = 0_u32
    @texture_depth = 0_u32
    @framecount = 0
    @starttime = Time.monotonic
  end

  def set_clut(clut)
    @clut_x = (clut & 0x3F) << 4
    @clut_y = (clut >> 6) & 0x1FF
  end

  def set_draw_params(params)
    @page_x = (params & 0xF) << 6
    @page_y = ((params >> 4) & 1) << 8
    @texture_depth = (params >> 7) & 3
  end

  def get_texel_4bit(x, y) : UInt16
    texel = vram_read(@page_x + x // 4, @page_y + y)
    index = (texel >> (x % 4) * 4) & 0xF
    vram_read(@clut_x + index, @clut_y)
  end

  def get_texel_8bit(x, y) : UInt16
    texel = vram_read(@page_x + x // 2, @page_y + y)
    index = (texel >> (x % 2) * 4) & 0xFF
    vram_read(@clut_x + index, @clut_y)
  end

  def get_texel_16bit(x, y) : UInt16
    vram_read(@page_x + x, @page_y + y)
  end

  def vram_read(x, y) : UInt16
    @vram[y][x]
  end

  def draw_textures(positions)
    xlen = positions[1][0] - positions[0][0]
    ylen = positions[2][1] - positions[0][1]
    (0...ylen).each do |y|
      (0...xlen).each do |x|
        case @texture_depth
        when 0
          pixel = get_texel_4bit(x, y)
        when 1
          pixel = get_texel_8bit(x, y)
        when 2
          pixel = get_texel_16bit(x, y)
        else
          pixel = 0x00_u16
        end
        r = (pixel << 3) & 0xF8
        g = (pixel >> 2) & 0xF8
        b = (pixel >> 7) & 0xF8
        if pixel != 0
          shape = SF::RectangleShape.new(SF.vector2(1, 1))
          shape.position = SF.vector2(positions[0][0] + x, positions[0][1] + y)
          shape.fill_color = SF::Color.new(r, g, b)
          @window.draw shape
        end
      end
    end
    @window.display
  end

  def load_image(top_left, resolution, buffer : Array(UInt16))
    pixels = Array(UInt8).new
    buffer.each do |pixel|
      a = 255_u8 #((pixel & 0x8000) >> 15) == 1 ? 255_u8 : 255_u8 #255_u8
      r = ((pixel << 3) & 0xf8).to_u8
      g = ((pixel >> 2) & 0xf8).to_u8
      b = ((pixel >> 7) & 0xf8).to_u8
      pixels << r
      pixels << g
      pixels << b
      pixels << a
    end
    @texture.update(pixels.to_unsafe.as(UInt8*), resolution[0], resolution[1], top_left[0], top_left[1])

    (top_left[1]...top_left[1] + resolution[1]).each do |y|
      @vram[y][top_left[0]...top_left[0]+resolution[0]] = buffer[(y-top_left[1])*resolution[0]...(y-top_left[1])*resolution[0] + resolution[0]]
    end
  end

  def push_triangle(vertices)
    if @nvertices + 3 > VERTEX_BUFFER_LEN
      puts "Vertex buffer full, drawing"
      draw
    end
    (0...3).each do |i|
      @vertices[@nvertices] = vertices[i]
      @nvertices += 1
    end
  end

  def push_quad(vertices)
    if @nvertices + 6 > VERTEX_BUFFER_LEN
      draw
    end
    (0...3).each do |i|
      @vertices[@nvertices] = vertices[i]
      @nvertices += 1
    end
    (1...4).each do |i|
      @vertices[@nvertices] = vertices[i]
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
        triangle[i] = @vertices[j*3 + i]
      end
      @window.draw triangle
    end
    @window.draw @sprite
    @window.display
    @nvertices = 0
    @framecount += 1
    #@window.title = "CryStation - FPS: #{(@framecount / (Time.monotonic - @starttime).seconds).to_i}"
  end
end
