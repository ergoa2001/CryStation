require "gl"
require "glfw"

class Renderer
  WIDTH  = 1024
  HEIGHT = 512
  def initialize
    GLFW.init
    GLFW.window_hint(GLFW::Hint::ContextVersionMajor, 3)
    GLFW.window_hint(GLFW::Hint::ContextVersionMinor, 3)
    @window = GLFW.create_window(WIDTH, HEIGHT, "CryStation")
    GLFW.set_current_context(@window)
    #@shader_program = ShaderProgram.new("./src/shaders/cube.vert", "./src/shaders/cube.frag")
    GL.clear_color(0.0, 0.0, 0.0, 1.0)
    GL.clear(GL::BufferBit::Color)
    GLFW.swap_buffers(@window)
  end
end
