const std = @import("std");
const c = @import("c.zig").c;

pub fn main() !void {
    std.log.info("Hello World!", .{});

    std.log.info("IMGUI_DISABLE_DEBUG_TOOLS: {any}", .{@hasDecl(c, "IMGUI_DISABLE_DEBUG_TOOLS")});

    const instance = c.wgpuCreateInstance(null);

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.log.err("SDL initialization failed: {s}\n", .{c.SDL_GetError()});

        std.process.exit(1);
    }
    const window: ?*c.SDL_Window = null;

    if (c.SDL_CreateWindow("Particle Simulation 2D", 1360, 768, 0) == null) {
        std.process.exit(1);
    }

    const surface = c.SDL_GetWGPUSurface(instance, window);

    std.log.info("Surface Created: {any}", .{surface});

    defer {
        c.SDL_DestroyWindow(window);
        c.SDL_Quit();
    }

    if (c.ImGui_CreateContext(null) == null) {
        std.log.err("ImGui initialization failed: {s}\n", .{c.SDL_GetError()});
        std.process.exit(1);
    }

    var event: c.SDL_Event = undefined;
    event_loop: while (true) {
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    std.log.info("Quitting...\n", .{});
                    break :event_loop;
                },
                else => {},
            }
        }
    }
}
