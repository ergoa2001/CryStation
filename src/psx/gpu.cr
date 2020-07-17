require "./renderer"

struct CommandBuffer
  @buffer : Array(UInt32)
  def initialize
    @buffer = Array.new(12, 0_u32)
    @len = 0
  end

  def clear
    @len = 0
  end

  def push_word(word : UInt32)
    @buffer[@len] = word
    @len += 1
  end

  def word(index)
    @buffer[index]
  end
end

struct ImageBuffer
  @buffer : Array(UInt16)
  VRAM_SIZE_PIXELS = 1024 * 512
  def initialize
    @buffer = Array.new(VRAM_SIZE_PIXELS, 0_u16)
    @top_left = {0, 0}
    @resolution = {0, 0}
    @index = 0
  end

  def clear
    @top_left = {0, 0}
    @resolution = {0, 0}
    @index = 0
    @buffer = Array.new(VRAM_SIZE_PIXELS, 0_u16)
  end

  def top_left
    @top_left
  end

  def resolution
    @resolution
  end

  def getbuffer
    len = @resolution[0] * @resolution[1]
    @buffer[0, len]
  end

  def reset(x : UInt16, y : UInt16, width : UInt16, height : UInt16)
    @top_left = {x, y}
    @resolution = {width, height}
    @index = 0
  end

  def push_gp0_word(word : UInt32)
    @buffer[@index] = word.to_u16!
    @index += 1
    @buffer[@index] = (word >> 16).to_u16!
    @index += 1
  end
end

struct Gpu
  enum TextureDepth : UInt32
    T4Bit
    T8Bit
    T16Bit
  end
  enum Field : UInt32
    Bottom
    Top
  end
  enum VerticalRes : UInt32
    Y240Lines
    Y480Lines
  end
  enum VMode : UInt32
    Ntsc
    Pal
  end
  enum DisplayDepth : UInt32
    D15Bits
    D24Bits
  end
  enum DmaDirection : UInt32
    Off
    Fifo
    CpuToGp0
    VRamToCpu
  end
  enum Gp0Mode
    Command
    ImageLoad
  end

  def from_fields(hr1 : UInt8, hr2 : UInt8)
    v = (hr2 & 1) | ((hr1 & 3) << 1)
    v.to_u32
  end

  def read : UInt32
    temp = @response
    @response = 0x00_u32
    temp
  end

  @gp0_command_method : Proc(Void)

  def initialize(counters : Counters)
    @counters = counters
    @page_base_x = 0_u8
    @page_base_y = 0_u8
    @semi_transparency = 0_u8
    @texture_depth = TextureDepth::T4Bit
    @dithering = false
    @draw_to_display = false
    @force_set_mask_bit = false
    @preserve_masked_pixels = false
    @field = Field::Top
    @texture_disable = false
    @hres = 0_u32
    @vres = VerticalRes::Y240Lines
    @vmode = VMode::Ntsc
    @display_depth = DisplayDepth::D15Bits
    @interlaced = false
    @display_disabled = true
    @interrupt = false
    @dma_direction = DmaDirection::Off
    @rectangle_texture_x_flip = false
    @rectangle_texture_y_flip = false
    @texture_window_x_mask = 0_u8
    @texture_window_y_mask = 0_u8
    @texture_window_x_offset = 0_u8
    @texture_window_y_offset = 0_u8
    @drawing_area_left = 0_u16
    @drawing_area_top = 0_u16
    @drawing_area_right = 0_u16
    @drawing_area_bottom = 0_u16
    @drawing_x_offset = 0_i16
    @drawing_y_offset = 0_i16
    @display_vram_x_start = 0_u16
    @display_vram_y_start = 0_u16
    @display_horiz_start = 0_u16
    @display_horiz_end = 0_u16
    @display_line_start = 0_u16
    @display_line_end = 0_u16

    @gp0_command = CommandBuffer.new
    @gp0_words_remaining = 0_u32
    @gp0_command_method = ->gp0_nop
    @gp0_mode = Gp0Mode::Command

    @renderer = Renderer.new
    @load_buffer = ImageBuffer.new

    @response = 0_u32 #TODO: make it a queue
  end

  def position_from_gp0(val : UInt32)
    x = val.to_u16!
    y = (val >> 16).to_u16!
    {x, y}
  end

  def color_from_gp0(val : UInt32)
    r = val.to_u8!
    g = (val >> 8) .to_u8!
    b = (val >> 16).to_u8!
    {r, g, b}
  end

  def status : UInt32
    r = 0_u32
    r |= @page_base_x.to_u32 << 0
    r |= @page_base_y.to_u32 << 4
    r |= @semi_transparency.to_u32 << 5
    r |= @texture_depth.value << 7
    r |= @dithering ? 1_u32 << 9 : 0_u32 << 9
    r |= @draw_to_display ? 1_u32 << 10 : 0_u32 << 10
    r |= @force_set_mask_bit ? 1_u32 << 11 : 0_u32 << 11
    r |= @preserve_masked_pixels ? 1_u32 << 12 : 0_u32 << 12
    r |= @field.value << 13
    # Bit 14: not supported
    r |= @texture_disable ? 1_u32 << 15 : 0_u32 << 15
    r |= @hres << 16
    #r |= @vres.value << 19
    r |= @vmode.value << 20
    r |= @display_depth.value << 21
    r |= @interlaced ? 1_u32 << 22 : 0_u32 << 22
    r |= @display_disabled ? 1_u32 << 23 : 0_u32 << 23
    r |= @interrupt ? 1_u32 << 24 : 0_u32 << 24
    r |= 1 << 26
    r |= 1 << 27
    r |= 1 << 28
    r |= @dma_direction.value << 29
    r |= 0 << 31
    dma_request = case @dma_direction
    when DmaDirection::Off then 0
    when DmaDirection::Fifo then 1
    when DmaDirection::CpuToGp0 then (r >> 28) & 1
    when DmaDirection::VRamToCpu then (r >> 27) & 1
    end
    r |= dma_request << 25
    r
  end

  def gp0_fill_rectangle
    color = color_from_gp0(@gp0_command.word(0))
    position = position_from_gp0(@gp0_command.word(1))
    size = position_from_gp0(@gp0_command.word(2))
    puts "fill rectangle #{color}, #{position}, #{size}"
  end

  def gp0_rect_texture_16_16_semi_raw
    # Color is ignored for raw texture
    size = {16, 16}
    top_left = position_from_gp0(@gp0_command.word(1))
    positions = [
      top_left,
      {top_left[0] + size[0], top_left[1]},
      {top_left[0], top_left[1] + size[1]},
      {top_left[0] + size[0], top_left[1] + size[1]}
    ]
    @renderer.set_clut(@gp0_command.word(2) >> 16)
    @renderer.draw_textures(positions)
  end

  def gp0_dot_opaque
    color = color_from_gp0(@gp0_command.word(0))
    positions = [
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(1))
    ]
    vertices = [
      SF::Vertex.new(SF.vector2(positions[0][0], positions[0][1]), SF.color(color[0], color[1], color[2])),
      SF::Vertex.new(SF.vector2(positions[1][0] + 1, positions[1][1]), SF.color(color[0], color[1], color[2])),
      SF::Vertex.new(SF.vector2(positions[2][0], positions[2][1] + 1), SF.color(color[0], color[1], color[2])),
      SF::Vertex.new(SF.vector2(positions[3][0] + 1, positions[3][1] + 1), SF.color(color[0], color[1], color[2]))
    ]
    @renderer.push_quad(vertices)
  end

  def gp0_poly_mono_semi
    color = color_from_gp0(@gp0_command.word(0))
    positions = [
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(2)),
      position_from_gp0(@gp0_command.word(3)),
      position_from_gp0(@gp0_command.word(4))
    ]
    vertices = [
      SF::Vertex.new(SF.vector2(positions[0][0], positions[0][1]), SF.color(color[0], color[1], color[2], 124)),
      SF::Vertex.new(SF.vector2(positions[1][0], positions[1][1]), SF.color(color[0], color[1], color[2], 124)),
      SF::Vertex.new(SF.vector2(positions[2][0], positions[2][1]), SF.color(color[0], color[1], color[2], 124)),
      SF::Vertex.new(SF.vector2(positions[3][0], positions[3][1]), SF.color(color[0], color[1], color[2], 124))
    ]
    @renderer.push_quad(vertices)
  end

  def gp0_mono_rect_var_semi
    color = color_from_gp0(@gp0_command.word(0))
    size = position_from_gp0(@gp0_command.word(2))
    positions = [
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(1))
    ]
    vertices = [
      SF::Vertex.new(SF.vector2(positions[0][0], positions[0][1]), SF.color(color[0], color[1], color[2], 124)),
      SF::Vertex.new(SF.vector2(positions[1][0] + size[0], positions[1][1]), SF.color(color[0], color[1], color[2], 124)),
      SF::Vertex.new(SF.vector2(positions[2][0], positions[2][1] + size[1]), SF.color(color[0], color[1], color[2], 124)),
      SF::Vertex.new(SF.vector2(positions[3][0] + size[0], positions[3][1] + size[1]), SF.color(color[0], color[1], color[2], 124))
    ]
    @renderer.push_quad(vertices)
  end

  def gp0_mono_rect_var_opaque
    color = color_from_gp0(@gp0_command.word(0))
    size = position_from_gp0(@gp0_command.word(2))
    positions = [
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(1))
    ]
    vertices = [
      SF::Vertex.new(SF.vector2(positions[0][0], positions[0][1]), SF.color(color[0], color[1], color[2])),
      SF::Vertex.new(SF.vector2(positions[1][0] + size[0], positions[1][1]), SF.color(color[0], color[1], color[2])),
      SF::Vertex.new(SF.vector2(positions[2][0], positions[2][1] + size[1]), SF.color(color[0], color[1], color[2])),
      SF::Vertex.new(SF.vector2(positions[3][0] + size[0], positions[3][1] + size[1]), SF.color(color[0], color[1], color[2]))
    ]
    @renderer.push_quad(vertices)
  end

  def gp0(val : UInt32)
    if @gp0_words_remaining == 0
      opcode = (val >> 24) & 0xFF
      len, method = case opcode
      when 0x00 then {1_u32, ->gp0_nop}
      when 0x01 then {1_u32, ->gp0_clear_cache}
      when 0x02 then {3_u32, ->gp0_fill_rectangle}
      when (0x04..0x1E) then {1_u32, ->gp0_nop}
      when 0x28 then {5_u32, ->gp0_quad_mono_opaque}
      when 0x2A then {5_u32, ->gp0_poly_mono_semi}
      when 0x2C then {9_u32, ->gp0_quad_texture_blend_opaque}
      when 0x30 then {6_u32, ->gp0_triangle_shaded_opaque}
      when 0x38 then {8_u32, ->gp0_quad_shaded_opaque}
      when 0x60 then {3_u32, ->gp0_mono_rect_var_opaque}
      when 0x62 then {3_u32, ->gp0_mono_rect_var_semi}
      when 0x68 then {2_u32, ->gp0_dot_opaque}
      when 0x7F then {3_u32, ->gp0_rect_texture_16_16_semi_raw} #broken
      when 0xA0 then {3_u32, ->gp0_image_load}
      when 0xC0 then {3_u32, ->gp0_image_store}
      when 0xE1 then {1_u32, ->gp0_draw_mode}
      when 0xE2 then {1_u32, ->gp0_texture_window}
      when 0xE3 then {1_u32, ->gp0_drawing_area_top_left}
      when 0xE4 then {1_u32, ->gp0_drawing_area_bottom_right}
      when 0xE5 then {1_u32, ->gp0_drawing_offset}
      when 0xE6 then {1_u32, ->gp0_mask_bit_setting}
      else raise "Unhandled GP0 command 0x#{val.to_s(16)}"
      end
      @gp0_words_remaining = len
      @gp0_command_method = method
      @gp0_command.clear
    end
    @gp0_words_remaining -= 1
    case @gp0_mode
    when Gp0Mode::Command
      @gp0_command.push_word(val)
      if @gp0_words_remaining == 0
        @gp0_command_method.call
      end
    when Gp0Mode::ImageLoad
      @load_buffer.push_gp0_word(val)
      if @gp0_words_remaining == 0
        @renderer.load_image(@load_buffer.top_left, @load_buffer.resolution, @load_buffer.getbuffer)
        @load_buffer.clear
        @gp0_mode = Gp0Mode::Command
      end
    end
  end

  def gp1(val : UInt32)
    opcode = (val >> 24) & 0xFF
    case opcode
    when 0x00 then gp1_reset(val)
    when 0x01 then gp1_reset_command_buffer
    when 0x02 then gp1_acknowledge_irq
    when 0x03 then gp1_display_enable(val)
    when 0x04 then gp1_dma_direction(val)
    when 0x05 then gp1_display_vram_start(val)
    when 0x06 then gp1_display_horizontal_range(val)
    when 0x07 then gp1_display_vertical_range(val)
    when 0x08 then gp1_display_mode(val)
    when 0x09 then gp1_new_texture_disable
    when 0x10 then gp1_get_gpu_info
    else raise "Unhandled GP1 command 0x#{val.to_s(16)}"
    end
  end

  def gp1_new_texture_disable

  end

  def gp1_get_gpu_info
    @response = 0x01_u32
  end

  def gp1_reset_command_buffer
    @gp0_command.clear
    @gp0_words_remaining = 0
    @gp0_mode = Gp0Mode::Command
  end

  def gp1_acknowledge_irq
    @interrupt = false
  end

  def gp0_quad_texture_blend_opaque
    positions = [
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(3)),
      position_from_gp0(@gp0_command.word(5)),
      position_from_gp0(@gp0_command.word(7))
    ]
    color = color_from_gp0(@gp0_command.word(0))
    @renderer.set_clut(@gp0_command.word(2) >> 16)
    @renderer.set_draw_params(@gp0_command.word(4) >> 16)

    @renderer.draw_textures(positions)
  end

  def gp0_triangle_shaded_opaque
    positions = [
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(3)),
      position_from_gp0(@gp0_command.word(5))
    ]

    colors = [
      color_from_gp0(@gp0_command.word(0)),
      color_from_gp0(@gp0_command.word(2)),
      color_from_gp0(@gp0_command.word(4))
    ]
    vertices = [
      SF::Vertex.new(SF.vector2(positions[0][0], positions[0][1]), SF.color(colors[0][0], colors[0][1], colors[0][2])),
      SF::Vertex.new(SF.vector2(positions[1][0], positions[1][1]), SF.color(colors[1][0], colors[1][1], colors[1][2])),
      SF::Vertex.new(SF.vector2(positions[2][0], positions[2][1]), SF.color(colors[2][0], colors[2][1], colors[2][2]))
    ]
    @renderer.push_triangle(vertices)
  end

  def gp0_image_store
    res = @gp0_command.word(2)
    width = res & 0xFFFF
    height = res >> 16
    @response = @renderer.vram_read(width, height).to_u32
    puts "Unhandled image store #{width}, #{height}"
  end

  def gp0_quad_shaded_opaque
    positions = [
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(3)),
      position_from_gp0(@gp0_command.word(5)),
      position_from_gp0(@gp0_command.word(7))
    ]
    colors = [
      color_from_gp0(@gp0_command.word(0)),
      color_from_gp0(@gp0_command.word(2)),
      color_from_gp0(@gp0_command.word(4)),
      color_from_gp0(@gp0_command.word(6))
    ]
    vertices = [
      SF::Vertex.new(SF.vector2(positions[0][0], positions[0][1]), SF.color(colors[0][0], colors[0][1], colors[0][2])),
      SF::Vertex.new(SF.vector2(positions[1][0], positions[1][1]), SF.color(colors[1][0], colors[1][1], colors[1][2])),
      SF::Vertex.new(SF.vector2(positions[2][0], positions[2][1]), SF.color(colors[2][0], colors[2][1], colors[2][2])),
      SF::Vertex.new(SF.vector2(positions[3][0], positions[3][1]), SF.color(colors[3][0], colors[3][1], colors[3][2]))
    ]
    @renderer.push_quad(vertices)
  end

  def gp1_display_enable(val : UInt32)
    @display_disabled = val & 1 != 0
  end

  def gp0_image_load
    pos = @gp0_command.word(1)
    x = pos & 0xFFFF
    y = pos >> 16

    res = @gp0_command.word(2)
    width = res & 0xFFFF
    height = res >> 16
    imgsize = width * height
    imgsize = (imgsize + 1) & ~1
    @gp0_words_remaining = imgsize // 2
    @load_buffer.reset(x.to_u16, y.to_u16, width.to_u16, height.to_u16)
    @gp0_mode = Gp0Mode::ImageLoad
  end

  def gp0_clear_cache
  end

  def gp0_quad_mono_opaque
    positions = [
      position_from_gp0(@gp0_command.word(1)),
      position_from_gp0(@gp0_command.word(2)),
      position_from_gp0(@gp0_command.word(3)),
      position_from_gp0(@gp0_command.word(4))
    ]
    colors = Array.new(4, color_from_gp0(@gp0_command.word(0)))
    vertices = [
      SF::Vertex.new(SF.vector2(positions[0][0], positions[0][1]), SF.color(colors[0][0], colors[0][1], colors[0][2])),
      SF::Vertex.new(SF.vector2(positions[1][0], positions[1][1]), SF.color(colors[1][0], colors[1][1], colors[1][2])),
      SF::Vertex.new(SF.vector2(positions[2][0], positions[2][1]), SF.color(colors[2][0], colors[2][1], colors[2][2])),
      SF::Vertex.new(SF.vector2(positions[3][0], positions[3][1]), SF.color(colors[3][0], colors[3][1], colors[3][2]))
    ]
    @renderer.push_quad(vertices)
  end

  def gp0_nop
  end

  def gp1_display_horizontal_range(val : UInt32)
    @display_horiz_start = (val & 0xFFF).to_u16
    @display_horiz_end = ((val >> 12) & 0xFFF).to_u16
  end

  def gp1_display_vertical_range(val : UInt32)
    @display_line_start = (val & 0x3FF).to_u16
    @display_line_end = ((val >> 10) & 0x3FF).to_u16
  end

  def gp1_display_vram_start(val : UInt32)
    @display_vram_x_start = (val & 0x3FE).to_u16
    @display_vram_y_start = ((val >> 10) & 0x1FF).to_u16
  end

  def gp0_mask_bit_setting
    val = @gp0_command.word(1)
    @force_set_mask_bit = (val & 1) != 0
    @preserve_masked_pixels = (val & 2) != 0
  end

  def gp0_texture_window
    val = @gp0_command.word(1)
    @texture_window_x_mask = (val & 0x1F).to_u8
    @texture_window_y_mask = ((val >> 5) & 0x1F).to_u8
    @texture_window_x_offset = ((val >> 10) & 0x1F).to_u8
    @texture_window_y_offset = ((val >> 15) & 0x1F).to_u8
  end

  def gp0_drawing_offset
    val = @gp0_command.word(1)
    x = (val & 0x7FF).to_u16
    y = ((val >> 11) & 0x7FF).to_u16
    @drawing_x_offset = (x << 5).to_i16! >> 5
    @drawing_y_offset = (y << 5).to_i16! >> 5

    @renderer.draw
    @counters.frame.increment
  end

  def gp0_drawing_area_bottom_right
    val = @gp0_command.word(1)
    @drawing_area_bottom = ((val >> 10) & 0x3FF).to_u16
    @drawing_area_right = (val & 0x3FF).to_u16
  end


  def gp0_drawing_area_top_left
    val = @gp0_command.word(1)
    @drawing_area_top = ((val >> 10) & 0x3FF).to_u16
    @drawing_area_left = (val & 0x3FF).to_u16
  end

  def gp1_dma_direction(val : UInt32)
    @dma_direction = case val & 3
    when 0 then DmaDirection::Off
    when 1 then DmaDirection::Fifo
    when 2 then DmaDirection::CpuToGp0
    when 3 then DmaDirection::VRamToCpu
    else raise "Unreachable DMA direction"
    end
  end

  def gp1_display_mode(val : UInt32)
    hr1 = (val & 3).to_u8
    hr2 = ((val >> 6) & 1).to_u8
    @hres = from_fields(hr1, hr2)
    @vres = val & 0x4 != 0 ? VerticalRes::Y480Lines : VerticalRes::Y240Lines
    @vmode = val & 0x8 != 0 ? VMode::Pal : VMode::Ntsc
    @display_depth = val & 0x10 != 0 ? DisplayDepth::D15Bits : DisplayDepth::D24Bits
    @interlaced = val & 0x20 != 0
    if val & 0x80 != 0
      raise "Unsupported display mode 0x#{val.to_s(16)}"
    end
  end


  def gp1_reset(val : UInt32)
    @interrupt = false
    @page_base_x = 0_u8
    @page_base_y = 0_u8
    @semi_transparency = 0_u8
    @texture_depth = TextureDepth::T4Bit
    @texture_window_x_mask = 0_u8
    @texture_window_y_mask = 0_u8
    @texture_window_x_offset = 0_u8
    @texture_window_y_offset = 0_u8
    @dithering = false
    @draw_to_display = false
    @texture_disable = false
    @rectangle_texture_x_flip = false
    @rectangle_texture_y_flip = false
    @drawing_area_left = 0_u16
    @drawing_area_top = 0_u16
    @drawing_area_right = 0_u16
    @drawing_area_bottom = 0_u16
    @drawing_x_offset = 0_i16
    @drawing_y_offset = 0_i16
    @force_set_mask_bit = false
    @preserve_masked_pixels = false

    @dma_direction = DmaDirection::Off

    @display_disabled = true
    @display_vram_x_start = 0_u16
    @display_vram_y_start = 0_u16
    @hres = 0_u32
    @vres = VerticalRes::Y240Lines

    @vmode = VMode::Ntsc
    @interlaced = true
    @display_horiz_start = 0x200_u16
    @display_horiz_end = 0xC00_u16
    @display_line_start = 0x10_u16
    @display_line_end = 0x100_u16
    @display_depth = DisplayDepth::D15Bits

    gp1_reset_command_buffer
  end

  def gp0_draw_mode
    val = @gp0_command.word(1)
    @page_base_x = (val & 0xF).to_u8
    @page_base_y = ((val >> 4) & 1).to_u8
    @semi_transparency = ((val >> 5) & 3).to_u8
    @texture_depth = case (val >> 7) & 3
    when 0 then TextureDepth::T4Bit
    when 1 then TextureDepth::T8Bit
    when 2 then TextureDepth::T16Bit
    else raise "Unhandled texture depth #{(val >> 7) & 3}"
    end
    @dithering = ((val >> 9) & 1) != 0
    @draw_to_display = ((val >> 10) & 1) != 0
    @texture_disable = ((val >> 11) & 1) != 0
    @rectangle_texture_x_flip = ((val >> 12) & 1) != 0
    @rectangle_texture_y_flip = ((val >> 13) & 1) != 0
  end
end
