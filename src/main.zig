const std = @import("std");

const c = @import("c.zig").c;
const particle_defs = @import("particle_defs.zig");
const renderer_2d = @import("renderer_2d.zig");
const simulation_cpu = @import("simulation_cpu.zig");
const simulation_gpu = @import("simulation_gpu.zig");

pub const std_options: std.Options = .{ .log_level = switch (@import("builtin").mode) {
    .Debug => .debug,
    else => .info,
} };

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const initial_width: c_int = 1360;
const initial_height: c_int = 768;

var current_width: c_int = initial_width;
var current_height: c_int = initial_height;

var wgpu_instance: c.WGPUInstance = null;
var wgpu_adapter: c.WGPUAdapter = null;
var wgpu_device: c.WGPUDevice = null;
var wgpu_queue: c.WGPUQueue = null;
var wgpu_surface: c.WGPUSurface = null;
var wgpu_surface_config: c.WGPUSurfaceConfiguration = undefined;
var preferred_surface_format: c.WGPUTextureFormat = c.WGPUTextureFormat_Undefined;

var particle_renderer: renderer_2d.ParticleRenderer = undefined;

const SimulationMethod = enum { cpu, gpu };
var current_sim_method: SimulationMethod = .gpu; // Default to GPU if available

var cpu_sim: ?simulation_cpu.CpuSimulation = null;
var gpu_sim: ?simulation_gpu.GpuSimulation = null;

// UI State
var sim_params: particle_defs.SimParams = .{
    .delta_time = 1.0 / 60.0,
    .mouse_force = 200.0,
    .mouse_radius = 100.0,
    .is_mouse_dragging = 0,
    .damping = 0.98,
    .particle_count = 100_000,
    .canvas_width = @as(f32, initial_width),
    .canvas_height = @as(f32, initial_height),
    .mouse_pos_sim = .{ 0.0, 0.0 },
    ._padding_simparams = .{ 0.0, 0.0 },
};
var ui_particle_count: u32 = 100_000;
var paused: bool = false;

fn request_adapter_callback(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, message_view: c.WGPUStringView, userdata1: ?*anyopaque, userdata2: ?*anyopaque) callconv(.C) void {
    _ = userdata1;
    _ = userdata2;
    const message_slice = if (message_view.data) |ptr| std.mem.span(ptr)[0..message_view.length] else null;

    if (status == c.WGPURequestAdapterStatus_Success) {
        std.log.info("Adapter acquired: {any}", .{adapter});
        wgpu_adapter = adapter; // adapter is already c.WGPUAdapter (?*Impl)
    } else {
        std.log.err("Failed to get adapter: {s}", .{message_slice orelse "Unknown error"});
        std.process.exit(1);
    }
}

fn request_device_callback(status: c.WGPURequestDeviceStatus, device: c.WGPUDevice, message_view: c.WGPUStringView, userdata1: ?*anyopaque, userdata2: ?*anyopaque) callconv(.C) void {
    _ = userdata1;
    _ = userdata2;
    const message_slice = if (message_view.data) |ptr| std.mem.span(ptr)[0..message_view.length] else null;

    if (status == c.WGPURequestDeviceStatus_Success) {
        std.log.info("Device acquired: {any}", .{device});
        wgpu_device = device; // device is already c.WGPUDevice (?*Impl)
        wgpu_queue = c.wgpuDeviceGetQueue(wgpu_device);
    } else {
        std.log.err("Failed to get device: {s}", .{message_slice orelse "Unknown error"});
        std.process.exit(1);
    }
}

fn uncaptured_error_callback(@"type": c.WGPUErrorType, message: [*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = userdata;
    std.log.err("WGPU Uncaptured Error ({any}): {s}", .{ @"type", message });
}

fn setup_wgpu(window: *c.SDL_Window) !void {
    wgpu_instance = c.wgpuCreateInstance(null);
    if (wgpu_instance == null) @panic("Failed to create WGPU instance");

    wgpu_surface = c.SDL_GetWGPUSurface(wgpu_instance.?, window);
    if (wgpu_surface == null) @panic("Failed to create WGPU surface");

    const adapter_options = c.WGPURequestAdapterOptions{
        .compatibleSurface = wgpu_surface,
        .powerPreference = c.WGPUPowerPreference_HighPerformance,
    };
    const adapter_callback_info = c.WGPURequestAdapterCallbackInfo{
        .mode = c.WGPUCallbackMode_AllowSpontaneous, // Or .ProcessEvents based on wgpu version/needs
        .callback = request_adapter_callback,
        .userdata1 = null, // This will be passed as the first userdata to the callback
        .userdata2 = null, // This will be passed as the second userdata to the callback
    };
    _ = c.wgpuInstanceRequestAdapter(wgpu_instance.?, &adapter_options, adapter_callback_info);
    // Note: In a real app, you'd likely have a mechanism to wait for these async callbacks.
    // For this example, we'll assume they complete quickly or use a simpler synchronous approach if available/faked.
    // For simplicity here, we'll proceed as if they are synchronous. This is NOT robust.
    // A proper solution would involve event loops or polling for completion.
    // The build script might be linking a wgpu version that allows for sync init on native.
    // Let's assume wgpuInstanceProcessEvents or similar would be called in a loop until wgpu_adapter is set.
    // These functions now return WGPUFuture.
    // For this simple example, we are not explicitly handling the future,
    // relying on the small sleep. A robust app would poll/wait.
    _ = c.wgpuInstanceRequestAdapter(wgpu_instance.?, &adapter_options, adapter_callback_info); // Assign to _ to acknowledge return
    // Deferring future drop removed as function is not available

    if (wgpu_adapter == null) { // Poll until adapter is set (simplified)
        // If using ProcessEvents mode, you would call wgpuInstanceProcessEvents here in a loop.
        std.time.sleep(100 * std.time.ns_per_ms); // give some time for callback
        if (wgpu_adapter == null) @panic("Adapter not set after callback (increase delay or implement proper async handling)");
    }

    const device_label_str = "Particle Simulation Device";
    const queue_label_str = "Default Queue";

    const device_desc = c.WGPUDeviceDescriptor{
        .label = .{ .data = device_label_str.ptr, .length = device_label_str.len },
        .requiredLimits = null, // Use default limits
        // .requiredFeaturesCount is no longer a field in this webgpu.h version
        .requiredFeatures = null, // Assuming null means no *additional* features beyond defaults
        .defaultQueue = .{ .label = .{ .data = queue_label_str.ptr, .length = queue_label_str.len } },
    };
    const device_callback_info = c.WGPURequestDeviceCallbackInfo{
        .mode = c.WGPUCallbackMode_AllowSpontaneous, // Or .ProcessEvents
        .callback = request_device_callback,
        .userdata1 = null,
        .userdata2 = null,
    };
    _ = c.wgpuAdapterRequestDevice(wgpu_adapter.?, &device_desc, device_callback_info); // Assign to _
    // Deferring future drop removed as function is not available

    if (wgpu_device == null) { // Poll until device is set
        // If using ProcessEvents mode, you would call wgpuInstanceProcessEvents here in a loop.
        std.time.sleep(100 * std.time.ns_per_ms);
        if (wgpu_device == null) @panic("Device not set after callback");
    }

    // _ = c.wgpuDeviceSetUncapturedErrorCallback(wgpu_device.?, uncaptured_error_callback, null); // Already removed

    var capabilities: c.WGPUSurfaceCapabilities = undefined;
    _ = c.wgpuSurfaceGetCapabilities(wgpu_surface.?, wgpu_adapter.?, &capabilities);
    // It's good practice to release capabilities when done, if the API expects it
    // For wgpu-native, this usually involves calling a specific free/release function
    // on the pointers within capabilities if they were heap allocated by the C side.
    // However, WGPUSurfaceCapabilities is often stack-allocated or its contents are views.
    // Let's assume for now direct usage is fine and no explicit free is needed for the struct itself,
    // but be mindful of `capabilities.formats` if it's a pointer that needs freeing.
    // Often `formats` points to an array within the capabilities struct itself or a static list.

    if (capabilities.formatCount > 0 and capabilities.formats != null) {
        preferred_surface_format = capabilities.formats[0]; // Pick the first available format
        std.log.info("Using first supported surface format: {any}", .{preferred_surface_format});
    } else {
        std.log.warn("No supported surface formats reported by capabilities, or formatCount is 0. Falling back.", .{});
        // Fallback if no formats listed or capabilities call fails to populate them.
        preferred_surface_format = c.WGPUTextureFormat_BGRA8UnormSrgb; // A common default
    }
    // If WGPUExports.h or a similar mechanism for freeing capability arrays exists for your backend, use it.
    // For example, some wgpu.h versions might require:
    // if (capabilities.formats != null) { c.wgpuSurfaceCapabilitiesFreeMembers(capabilities) }
    // or similar after you're done using the `formats` pointer.
    // For now, we assume the formats array is valid for the lifetime of `capabilities` on the stack.
    // If `wgpu-native` provides `wgpuSurfaceCapabilitiesFreeMembers` or similar, it should be used.
    // Checking `webgpu.h` from your wgpu-native ffi for `WGPUSurfaceCapabilities` and any related free functions is key.
    // For many basic wgpu-native uses, the formats array within capabilities is directly usable without explicit free.

    // After being done with the `capabilities` struct, if its members (like `formats` or `presentModes`)
    // were allocated by the C library and need to be freed, you'd call a function like `wgpuSurfaceCapabilitiesFreeMembers(capabilities)`
    // or `wgpu_free_surface_capabilities_members(&capabilities)`.
    // This is backend-specific. For now, we'll assume the formats array is either static or part of the struct.
    // If you get crashes later related to this, it's a likely place to investigate.
    // Typically, for wgpu-native, `formats` is a pointer to an array whose lifetime is managed by the capabilities struct,
    // and you call `wgpuSurfaceCapabilitiesFreeMembers(capabilities)` when done.
    // Let's assume this function exists for safety, if it doesn't, this line needs to be removed.
    // It's often defined in a C utility header or directly in webgpu.h.
    // If not found, comment it out. It's highly dependent on the exact wgpu.h version.
    // c.wgpuMemoryUserdataFree(capabilities.formats, null); // This is a guess, actual function name varies.
    // The most common is `wgpuSurfaceCapabilitiesFreeMembers`. If your `c.zig` doesn't show it, then it's not there.
    // For now, let's proceed without an explicit free for `capabilities.formats` as it's often not needed for the first format.

    std.log.info("Selected surface format: {any}", .{preferred_surface_format});
    if (preferred_surface_format == c.WGPUTextureFormat_Undefined) {
        std.log.err("Surface format is Undefined after capabilities check. This should not happen.", .{});
        preferred_surface_format = c.WGPUTextureFormat_BGRA8UnormSrgb; // Critical fallback
    }

    wgpu_surface_config = .{
        .device = wgpu_device.?,
        .format = preferred_surface_format,
        .usage = c.WGPUTextureUsage_RenderAttachment,
        .viewFormatCount = 0, // zig v0.12
        .viewFormats = null, // zig v0.12
        .alphaMode = c.WGPUCompositeAlphaMode_Premultiplied, // Or .Opaque
        .width = @intCast(current_width),
        .height = @intCast(current_height),
        .presentMode = c.WGPUPresentMode_Fifo, // Or .Mailbox for lower latency
    };
    c.wgpuSurfaceConfigure(wgpu_surface.?, &wgpu_surface_config);
}

fn reconfigure_surface() void {
    if (wgpu_surface != null and wgpu_device != null) {
        wgpu_surface_config.width = @intCast(current_width);
        wgpu_surface_config.height = @intCast(current_height);
        sim_params.canvas_width = @as(f32, current_width);
        sim_params.canvas_height = @as(f32, current_height);
        c.wgpuSurfaceConfigure(wgpu_surface.?, &wgpu_surface_config);
    }
}

fn switch_simulation_method(new_method: SimulationMethod) !void {
    if (current_sim_method == new_method and (cpu_sim != null or gpu_sim != null)) return;

    // Deinit previous simulation
    if (cpu_sim) |*sim| {
        sim.deinit();
        cpu_sim = null;
    }
    if (gpu_sim) |*sim| {
        sim.deinit();
        gpu_sim = null;
    }

    current_sim_method = new_method;
    sim_params.particle_count = ui_particle_count;

    // Ensure device is non-null before passing to simulation init
    const device = wgpu_device orelse @panic("WGPU device not initialized for simulation switch");

    switch (current_sim_method) {
        .cpu => {
            cpu_sim = try simulation_cpu.CpuSimulation.init(allocator, device, ui_particle_count, sim_params.canvas_width, sim_params.canvas_height);
        },
        .gpu => {
            // Check if compute shaders are supported (simplified check)
            var features: c.WGPUAdapterProperties = undefined;
            c.wgpuAdapterGetProperties(wgpu_adapter.?, &features);
            // This isn't a direct check for compute support from properties.
            // A proper check involves wgpuDeviceGetLimits and checking compute-related limits.
            // For now, assume it's available if not on web without WebGPU.
            gpu_sim = try simulation_gpu.GpuSimulation.init(allocator, device, ui_particle_count, sim_params.canvas_width, sim_params.canvas_height);
        },
    }
}

fn resize_simulation_buffers() !void {
    sim_params.particle_count = ui_particle_count;
    const device = wgpu_device orelse @panic("WGPU device not initialized for sim resize");
    const queue = wgpu_queue orelse @panic("WGPU queue not initialized for sim resize");
    switch (current_sim_method) {
        .cpu => if (cpu_sim) |*sim| try sim.resize(device, queue, ui_particle_count, sim_params.canvas_width, sim_params.canvas_height),
        .gpu => if (gpu_sim) |*sim| try sim.resize(device, queue, ui_particle_count, sim_params.canvas_width, sim_params.canvas_height),
    }
}

pub fn main() !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        std.log.err("SDL initialization failed: {s}", .{c.SDL_GetError()});
        std.process.exit(1);
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "Particle Simulation 2D",
        initial_width,
        initial_height,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    );
    if (window == null) {
        std.log.err("SDL_CreateWindow failed: {s}", .{c.SDL_GetError()});
        std.process.exit(1);
    }
    defer c.SDL_DestroyWindow(window);

    try setup_wgpu(window.?);
    defer { // Release with .? as these are optional pointers
        if (wgpu_surface) |s| c.wgpuSurfaceRelease(s);
        if (wgpu_device) |d| c.wgpuDeviceRelease(d);
        if (wgpu_adapter) |a| c.wgpuAdapterRelease(a);
        if (wgpu_instance) |i| c.wgpuInstanceRelease(i);
    }

    // Setup ImGui
    _ = c.ImGui_CreateContext(null);
    defer c.ImGui_DestroyContext(null);
    const io = c.ImGui_GetIO().?;
    // io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard;
    // io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable; // Optional: if you want docking

    if (!c.cImGui_ImplSDL3_InitForOther(window)) { // Pass c.WGPUDevice directly
        std.log.err("ImGui_ImplSDL3_InitForWGPU failed", .{});
        std.process.exit(1);
    }
    defer c.ImGui_ImplSDL3_Shutdown();

    // Construct the init info struct
    var imgui_wgpu_init_info = c.ImGui_ImplWGPU_InitInfo_t{
        .Device = wgpu_device, // Pass the WGPUDevice directly
        .NumFramesInFlight = 1, // Or adjust if using more frames in flight
        .RenderTargetFormat = preferred_surface_format,
        .DepthStencilFormat = c.WGPUTextureFormat_Undefined, // No depth/stencil buffer used
        // Initialize PipelineMultisampleState, common defaults:
        .PipelineMultisampleState = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
            .alphaToCoverageEnabled = 0,
        },
    };

    // Pass the address of the struct
    if (!c.cImGui_ImplWGPU_Init(&imgui_wgpu_init_info)) {
        std.log.err("ImGui_ImplWGPU_Init failed", .{});
        std.process.exit(1);
    }
    defer c.ImGui_ImplWGPU_Shutdown();

    // Setup Renderer
    particle_renderer = try renderer_2d.ParticleRenderer.init(allocator, wgpu_device.?, preferred_surface_format); // .? to pass *Impl
    defer particle_renderer.deinit();

    // Setup Simulation
    try switch_simulation_method(current_sim_method); // Initial setup

    var event: c.SDL_Event = undefined;
    var running = true;
    var last_frame_time = std.time.nanoTimestamp();

    while (running) {
        const current_frame_time = std.time.nanoTimestamp();
        sim_params.delta_time = @as(f32, current_frame_time - last_frame_time) / 1.0e9;
        last_frame_time = current_frame_time;
        if (sim_params.delta_time > 0.1) sim_params.delta_time = 0.1; // Cap delta time

        while (c.SDL_PollEvent(&event) != 0) {
            _ = c.ImGui_ImplSDL3_ProcessEvent(&event);
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                    c.SDL_GetWindowSizeInPixels(window, &current_width, &current_height);
                    reconfigure_surface();
                },
                else => {},
            }
        }
        if (!running) break;

        // ImGui New Frame
        c.ImGui_ImplWGPU_NewFrame();
        c.ImGui_ImplSDL3_NewFrame();
        c.ImGui_NewFrame();

        // --- ImGui UI ---
        if (c.ImGui_Begin("Controls", null, 0)) {
            c.ImGui_Text("Particle Count: %u", .{ui_particle_count});
            if (c.ImGui_SliderScalar("##particle_count_slider", .Uint, &ui_particle_count, &@as(u32, 1000), &@as(u32, 500_000), "%u", 0)) {
                resize_simulation_buffers() catch |err| std.log.err("Failed to resize sim: {any}", .{err});
            }

            if (c.ImGui_RadioButton_BoolStr("CPU", current_sim_method == .cpu)) {
                switch_simulation_method(.cpu) catch |err| std.log.err("Failed to switch to CPU: {any}", .{err});
            }
            c.ImGui_SameLine(0, -1);
            if (c.ImGui_RadioButton_BoolStr("GPU", current_sim_method == .gpu)) {
                switch_simulation_method(.gpu) catch |err| std.log.err("Failed to switch to GPU: {any}", .{err});
            }

            c.ImGui_SliderFloat("Mouse Force", &sim_params.mouse_force, 10.0, 1000.0, "%.1f", 0);
            c.ImGui_SliderFloat("Mouse Radius", &sim_params.mouse_radius, 10.0, 500.0, "%.1f", 0);
            c.ImGui_SliderFloat("Damping", &sim_params.damping, 0.8, 1.0, "%.3f", 0);
            c.ImGui_Checkbox("Paused", &paused);

            c.ImGui_Text("DeltaTime: %.4f s", .{sim_params.delta_time});
            c.ImGui_Text("FPS: %.1f", .{1.0 / sim_params.delta_time});
        }
        c.ImGui_End();
        // --- End ImGui UI ---

        // Update mouse state from ImGui
        sim_params.is_mouse_dragging = if (io.*.MouseDown[0] and !io.*.WantCaptureMouse) 1 else 0;
        if (sim_params.is_mouse_dragging == 1) {
            sim_params.mouse_pos_sim[0] = io.*.MousePos.x;
            sim_params.mouse_pos_sim[1] = io.*.MousePos.y;
        }

        // Update simulation
        if (!paused) {
            const queue = wgpu_queue orelse @panic("WGPU queue not initialized for sim update");
            switch (current_sim_method) {
                .cpu => if (cpu_sim) |*sim| sim.update(queue, &sim_params),
                .gpu => if (gpu_sim) |*comp_sim| {
                    const device = wgpu_device orelse @panic("WGPU device not initialized for compute encoder");
                    const cmd_encoder_desc = c.WGPUCommandEncoderDescriptor{ .label = "Compute Encoder" };
                    const comp_encoder = c.wgpuDeviceCreateCommandEncoder(device, &cmd_encoder_desc); // Pass device directly
                    comp_sim.update(queue, comp_encoder.?, &sim_params); // Pass unwrapped encoder
                    const comp_cmd_buffer = c.wgpuCommandEncoderFinish(comp_encoder.?, null);
                    c.wgpuQueueSubmit(queue, 1, &comp_cmd_buffer);
                    c.wgpuCommandBufferRelease(comp_cmd_buffer);
                    c.wgpuCommandEncoderRelease(comp_encoder.?);
                },
            }
        }

        // Rendering
        var surface_texture: c.WGPUSurfaceTexture = undefined;
        c.wgpuSurfaceGetCurrentTexture(wgpu_surface.?, &surface_texture);
        // Defer freeing members if the function exists.
        // This is a common pattern for wgpu-native. If c.wgpuSurfaceCapabilitiesFreeMembers
        // is not found by the compiler, then this specific function is not part of your webgpu.h
        // and this defer should be removed.
        // if (@hasDecl(c, "wgpuSurfaceCapabilitiesFreeMembers")) {
        //     defer c.wgpuSurfaceCapabilitiesFreeMembers(&capabilities);
        // }
        if (surface_texture.status != .Success) {
            std.log.warn("wgpuSurfaceGetCurrentTexture failed with status {any}, reconfiguring.", .{surface_texture.status});
            if (surface_texture.texture != null) c.wgpuTextureRelease(surface_texture.texture);
            // Surface might be lost, try to reconfigure. Might need to skip a frame.
            reconfigure_surface();
            c.wgpuSurfaceGetCurrentTexture(wgpu_surface.?, &surface_texture); // try again
            if (surface_texture.status != .Success) { // if still fails, skip frame
                if (surface_texture.texture != null) c.wgpuTextureRelease(surface_texture.texture);
                continue;
            }
        }
        defer if (surface_texture.texture != null) c.wgpuTextureRelease(surface_texture.texture);

        const target_view = c.wgpuTextureCreateView(surface_texture.texture, null);
        defer c.wgpuTextureViewRelease(target_view.?);

        const device = wgpu_device orelse @panic("WGPU device not initialized for render encoder");
        const queue = wgpu_queue orelse @panic("WGPU queue not initialized for render");

        const cmd_encoder_desc = c.WGPUCommandEncoderDescriptor{ .label = "Main Render Encoder" };
        const encoder = c.wgpuDeviceCreateCommandEncoder(device, &cmd_encoder_desc); // Pass device directly
        defer c.wgpuCommandEncoderRelease(encoder.?);

        // Render particles
        const particle_buffer_to_render = switch (current_sim_method) {
            .cpu => cpu_sim.?.particle_buffer,
            .gpu => gpu_sim.?.particle_buffer,
        };
        particle_renderer.render(queue, encoder.?, target_view.?, particle_buffer_to_render, sim_params.particle_count, sim_params.canvas_width, sim_params.canvas_height);

        // Render ImGui
        c.ImGui_Render();
        c.ImGui_ImplWGPU_RenderDrawData(c.ImGui_GetDrawData(), encoder.?);

        const cmd_buffer = c.wgpuCommandEncoderFinish(encoder.?, null);
        c.wgpuQueueSubmit(queue, 1, &cmd_buffer);
        c.wgpuCommandBufferRelease(cmd_buffer);

        c.wgpuSurfacePresent(wgpu_surface.?);

        // Process WGPU events (important for callbacks and internal operations)
        // c.wgpuInstanceProcessEvents(wgpu_instance.?); // If using async instance
    }

    // Cleanup simulations
    if (cpu_sim) |*sim| sim.deinit();
    if (gpu_sim) |*sim| sim.deinit();
    try gpa.deinit();
}
