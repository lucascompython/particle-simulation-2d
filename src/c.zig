pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("sdl3webgpu.h");
    @cInclude("webgpu/webgpu.h");
    @cInclude("imgui_config.h");
    @cInclude("dcimgui.h");
    @cInclude("dcimgui_impl_sdl3.h");
    @cInclude("dcimgui_impl_wgpu.h");
});
