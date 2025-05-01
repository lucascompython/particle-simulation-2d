pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("sdl3webgpu.h");
    @cInclude("webgpu/webgpu.h");
});
