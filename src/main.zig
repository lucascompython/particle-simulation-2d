const std = @import("std");
const sdl = @import("sdl.zig").SDL;

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        std.debug.print("SDL initialization failed: {s}\n", .{sdl.SDL_GetError()});
        std.process.exit(1);
    }

    var window: ?*sdl.SDL_Window = null;
    var renderer: ?*sdl.SDL_Renderer = null;

    if (!sdl.SDL_CreateWindowAndRenderer("Particle Simulation 2D", 1360, 768, 0, &window, &renderer)) {
        std.process.exit(1);
    }

    defer {
        sdl.SDL_DestroyRenderer(renderer);
        sdl.SDL_DestroyWindow(window);
        sdl.SDL_Quit();
    }

    while (true) {
        var event: sdl.SDL_Event = undefined;
        if (sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => {
                    std.debug.print("Quitting...\n", .{});
                    break;
                },
                else => {},
            }
        }
    }
}
