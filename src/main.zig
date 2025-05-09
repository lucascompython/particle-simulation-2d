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

inline fn setupImGuiStyle(alpha_for_transparent_items: f32) void {
    const style_ptr = c.ImGui_GetStyle();
    if (style_ptr == null) {
        std.log.warn("ImGui_GetStyle() returned null, cannot apply custom style.", .{});
        return;
    }
    var style = style_ptr.*; // Make a mutable copy to work with

    style.Alpha = 1.0; // Overall alpha for the ImGui context
    style.FrameRounding = 3.0;
    style.WindowRounding = 3.0; // Add window rounding

    style.Colors[c.ImGuiCol_Text] = c.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 1.00 };
    style.Colors[c.ImGuiCol_TextDisabled] = c.ImVec4{ .x = 0.60, .y = 0.60, .z = 0.60, .w = 1.00 };
    style.Colors[c.ImGuiCol_WindowBg] = c.ImVec4{ .x = 0.94, .y = 0.94, .z = 0.94, .w = 1.00 }; // Made opaque
    style.Colors[c.ImGuiCol_ChildBg] = c.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.00 };
    style.Colors[c.ImGuiCol_PopupBg] = c.ImVec4{ .x = 1.00, .y = 1.00, .z = 1.00, .w = 1.00 }; // Made opaque
    style.Colors[c.ImGuiCol_Border] = c.ImVec4{ .x = 0.00, .y = 0.00, .z = 0.00, .w = 0.39 };
    style.Colors[c.ImGuiCol_BorderShadow] = c.ImVec4{ .x = 1.00, .y = 1.00, .z = 1.00, .w = 0.10 };
    style.Colors[c.ImGuiCol_FrameBg] = c.ImVec4{ .x = 0.90, .y = 0.90, .z = 0.90, .w = 1.00 }; // Adjusted for better dark mode contrast
    style.Colors[c.ImGuiCol_FrameBgHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.40 };
    style.Colors[c.ImGuiCol_FrameBgActive] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.67 };
    style.Colors[c.ImGuiCol_TitleBg] = c.ImVec4{ .x = 0.96, .y = 0.96, .z = 0.96, .w = 1.00 };
    style.Colors[c.ImGuiCol_TitleBgCollapsed] = c.ImVec4{ .x = 1.00, .y = 1.00, .z = 1.00, .w = 0.51 };
    style.Colors[c.ImGuiCol_TitleBgActive] = c.ImVec4{ .x = 0.82, .y = 0.82, .z = 0.82, .w = 1.00 };
    style.Colors[c.ImGuiCol_MenuBarBg] = c.ImVec4{ .x = 0.86, .y = 0.86, .z = 0.86, .w = 1.00 };
    style.Colors[c.ImGuiCol_ScrollbarBg] = c.ImVec4{ .x = 0.98, .y = 0.98, .z = 0.98, .w = 0.53 };
    style.Colors[c.ImGuiCol_ScrollbarGrab] = c.ImVec4{ .x = 0.69, .y = 0.69, .z = 0.69, .w = 1.00 };
    style.Colors[c.ImGuiCol_ScrollbarGrabHovered] = c.ImVec4{ .x = 0.59, .y = 0.59, .z = 0.59, .w = 1.00 };
    style.Colors[c.ImGuiCol_ScrollbarGrabActive] = c.ImVec4{ .x = 0.49, .y = 0.49, .z = 0.49, .w = 1.00 };
    style.Colors[c.ImGuiCol_CheckMark] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.00 };
    style.Colors[c.ImGuiCol_SliderGrab] = c.ImVec4{ .x = 0.24, .y = 0.52, .z = 0.88, .w = 1.00 };
    style.Colors[c.ImGuiCol_SliderGrabActive] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.00 };
    style.Colors[c.ImGuiCol_Button] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.40 };
    style.Colors[c.ImGuiCol_ButtonHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.00 };
    style.Colors[c.ImGuiCol_ButtonActive] = c.ImVec4{ .x = 0.06, .y = 0.53, .z = 0.98, .w = 1.00 };
    style.Colors[c.ImGuiCol_Header] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.31 };
    style.Colors[c.ImGuiCol_HeaderHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.80 };
    style.Colors[c.ImGuiCol_HeaderActive] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.00 };
    style.Colors[c.ImGuiCol_Separator] = c.ImVec4{ .x = 0.39, .y = 0.39, .z = 0.39, .w = 1.00 };
    style.Colors[c.ImGuiCol_SeparatorHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.78 };
    style.Colors[c.ImGuiCol_SeparatorActive] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.00 };
    style.Colors[c.ImGuiCol_ResizeGrip] = c.ImVec4{ .x = 1.00, .y = 1.00, .z = 1.00, .w = 0.50 };
    style.Colors[c.ImGuiCol_ResizeGripHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.67 };
    style.Colors[c.ImGuiCol_ResizeGripActive] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.95 };
    style.Colors[c.ImGuiCol_Tab] = c.ImVec4{ .x = 0.59, .y = 0.59, .z = 0.59, .w = 0.50 }; // Mapped from C++ CloseButton
    style.Colors[c.ImGuiCol_TabHovered] = c.ImVec4{ .x = 0.98, .y = 0.39, .z = 0.36, .w = 1.00 }; // Mapped from C++ CloseButtonHovered
    style.Colors[c.ImGuiCol_TabSelected] = c.ImVec4{ .x = 0.98, .y = 0.39, .z = 0.36, .w = 1.00 }; // Mapped from C++ CloseButtonActive
    // The following Tab states are not in the C++ style, using reasonable defaults or derivations
    style.Colors[c.ImGuiCol_TabSelectedOverline] = style.Colors[c.ImGuiCol_TabSelected]; // Or a more prominent color
    style.Colors[c.ImGuiCol_TabDimmed] = style.Colors[c.ImGuiCol_Tab]; // Or a dimmer version
    style.Colors[c.ImGuiCol_TabDimmedSelected] = style.Colors[c.ImGuiCol_TabSelected];
    style.Colors[c.ImGuiCol_TabDimmedSelectedOverline] = style.Colors[c.ImGuiCol_TabSelectedOverline];

    style.Colors[c.ImGuiCol_TextSelectedBg] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.35 };
    style.Colors[c.ImGuiCol_ModalWindowDimBg] = c.ImVec4{ .x = 0.20, .y = 0.20, .z = 0.20, .w = 0.35 };

    var i: c_int = 0;
    while (i < c.ImGuiCol_COUNT) : (i += 1) {
        var h: f32 = undefined;
        var s: f32 = undefined;
        var v: f32 = undefined;

        const original_w = style.Colors[@intCast(i)].w;
        const color_component_r = style.Colors[@intCast(i)].x;
        const color_component_g = style.Colors[@intCast(i)].y;
        const color_component_b = style.Colors[@intCast(i)].z;

        c.ImGui_ColorConvertRGBtoHSV(color_component_r, color_component_g, color_component_b, &h, &s, &v);

        if (s < 0.1) { // For greyscale colors, invert lightness
            v = 1.0 - v;
        }
        c.ImGui_ColorConvertHSVtoRGB(h, s, v, &style.Colors[@intCast(i)].x, &style.Colors[@intCast(i)].y, &style.Colors[@intCast(i)].z);

        // Apply alpha multiplier only to colors that were originally transparent
        if (original_w < 1.0) {
            style.Colors[@intCast(i)].w = original_w * alpha_for_transparent_items;
        } else { // If it was originally opaque, keep it opaque
            style.Colors[@intCast(i)].w = 1.0; // Ensure it's fully opaque if it started as such
        }
    }
    style_ptr.* = style;
}

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
    _ = c.wgpuInstanceRequestAdapter(wgpu_instance.?, &adapter_options, adapter_callback_info); // Assign to _ to acknowledge return
    // Deferring future drop removed as function is not available
    // Note: In a real app, you'd likely have a mechanism to wait for these async callbacks,
    // or ensure wgpuInstanceProcessEvents is called if using that callback mode.
    // For this example, we are relying on a small sleep after this single call.

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
        .alphaMode = c.WGPUCompositeAlphaMode_Opaque,
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
        sim_params.canvas_width = @floatFromInt(current_width);
        sim_params.canvas_height = @floatFromInt(current_height);
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
    defer c.cImGui_ImplSDL3_Shutdown();

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
    defer c.cImGui_ImplWGPU_Shutdown();

    // Apply custom ImGui style (e.g., dark style with full alpha modification)
    setupImGuiStyle(1.0);

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
        const delta: f32 = @as(f32, @floatFromInt(current_frame_time - last_frame_time)) / 1.0e9;
        sim_params.delta_time = delta;
        last_frame_time = current_frame_time;
        if (sim_params.delta_time > 0.1) sim_params.delta_time = 0.1; // Cap delta time

        while (c.SDL_PollEvent(&event)) {
            _ = c.cImGui_ImplSDL3_ProcessEvent(&event);
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                    _ = c.SDL_GetWindowSizeInPixels(window, &current_width, &current_height); // Explicitly ignore return value
                    reconfigure_surface();
                },
                else => {},
            }
        }
        if (!running) break;

        // ImGui New Frame
        c.cImGui_ImplWGPU_NewFrame();
        c.cImGui_ImplSDL3_NewFrame();
        c.ImGui_NewFrame();

        // --- ImGui UI ---
        if (c.ImGui_Begin("Controls", null, 0)) {
            c.ImGui_Text("Particle Count: %u", ui_particle_count);
            if (c.ImGui_SliderScalarEx("##particle_count_slider", c.ImGuiDataType_U32, &ui_particle_count, &@as(u32, 1000), &@as(u32, 500_000), "%u", 0)) {
                resize_simulation_buffers() catch |err| std.log.err("Failed to resize sim: {any}", .{err});
            }

            if (c.ImGui_RadioButton("CPU", current_sim_method == .cpu)) {
                switch_simulation_method(.cpu) catch |err| std.log.err("Failed to switch to CPU: {any}", .{err});
            }
            c.ImGui_SameLineEx(0.0, -1.0);
            if (c.ImGui_RadioButton("GPU", current_sim_method == .gpu)) {
                switch_simulation_method(.gpu) catch |err| std.log.err("Failed to switch to GPU: {any}", .{err});
            }

            _ = c.ImGui_SliderFloatEx("Mouse Force", &sim_params.mouse_force, 10.0, 1000.0, "%.1f", 0);
            _ = c.ImGui_SliderFloatEx("Mouse Radius", &sim_params.mouse_radius, 10.0, 500.0, "%.1f", 0);
            _ = c.ImGui_SliderFloatEx("Damping", &sim_params.damping, 0.8, 1.0, "%.3f", 0);
            _ = c.ImGui_Checkbox("Paused", &paused);

            c.ImGui_Text("DeltaTime: %.4f s", sim_params.delta_time);
            c.ImGui_Text("FPS: %.1f", @as(f64, 1.0 / sim_params.delta_time));
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
                    const compute_encoder_label_str = "Compute Encoder";
                    const cmd_encoder_desc = c.WGPUCommandEncoderDescriptor{ .label = .{ .data = compute_encoder_label_str.ptr, .length = compute_encoder_label_str.len } };
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
        if (surface_texture.status != c.WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal) {
            std.log.warn("wgpuSurfaceGetCurrentTexture failed with status {any}, reconfiguring.", .{surface_texture.status});
            if (surface_texture.texture != null) c.wgpuTextureRelease(surface_texture.texture);
            // Surface might be lost, try to reconfigure. Might need to skip a frame.
            reconfigure_surface();
            c.wgpuSurfaceGetCurrentTexture(wgpu_surface.?, &surface_texture); // try again
            if (surface_texture.status != c.WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal) { // if still fails, skip frame
                if (surface_texture.texture != null) c.wgpuTextureRelease(surface_texture.texture);
                continue;
            }
        }
        defer if (surface_texture.texture != null) c.wgpuTextureRelease(surface_texture.texture);

        const target_view = c.wgpuTextureCreateView(surface_texture.texture, null);
        defer c.wgpuTextureViewRelease(target_view.?);

        const device = wgpu_device orelse @panic("WGPU device not initialized for render encoder");
        const queue = wgpu_queue orelse @panic("WGPU queue not initialized for render");

        const render_encoder_label_str = "Main Render Encoder";
        const cmd_encoder_desc = c.WGPUCommandEncoderDescriptor{ .label = .{ .data = render_encoder_label_str.ptr, .length = render_encoder_label_str.len } };
        const encoder = c.wgpuDeviceCreateCommandEncoder(device, &cmd_encoder_desc); // Pass device directly

        // --- Render Particles ---
        const particle_buffer_to_render = switch (current_sim_method) {
            .cpu => cpu_sim.?.particle_buffer,
            .gpu => gpu_sim.?.particle_buffer,
        };
        particle_renderer.render(queue, encoder.?, target_view.?, particle_buffer_to_render, sim_params.particle_count, sim_params.canvas_width, sim_params.canvas_height);

        // --- Render ImGui in a new pass ---
        c.ImGui_Render();
        const imgui_render_pass_color_attachment = c.WGPURenderPassColorAttachment{
            .view = target_view.?, // Use the same target view
            .resolveTarget = null,
            .loadOp = c.WGPULoadOp_Load, // Load previous contents (particles)
            .storeOp = c.WGPUStoreOp_Store,
            .clearValue = c.WGPUColor{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 }, // Clear color not strictly needed due to LoadOp
        };
        const imgui_render_pass_label_str = "ImGui Render Pass";
        const imgui_render_pass_desc = c.WGPURenderPassDescriptor{
            .label = .{ .data = imgui_render_pass_label_str.ptr, .length = imgui_render_pass_label_str.len },
            .colorAttachmentCount = 1,
            .colorAttachments = &imgui_render_pass_color_attachment,
            .depthStencilAttachment = null,
            .timestampWrites = null,
        };

        const imgui_rpass = c.wgpuCommandEncoderBeginRenderPass(encoder.?, &imgui_render_pass_desc);
        c.cImGui_ImplWGPU_RenderDrawData(c.ImGui_GetDrawData(), imgui_rpass);
        c.wgpuRenderPassEncoderEnd(imgui_rpass);
        // --- End ImGui Render Pass ---

        const cmd_buffer = c.wgpuCommandEncoderFinish(encoder.?, null);
        c.wgpuQueueSubmit(queue, 1, &cmd_buffer);
        c.wgpuCommandBufferRelease(cmd_buffer);
        c.wgpuCommandEncoderRelease(encoder.?); // Release after use

        _ = c.wgpuSurfacePresent(wgpu_surface.?);

        // Process WGPU events (important for callbacks and internal operations)
        // c.wgpuInstanceProcessEvents(wgpu_instance.?); // If using async instance
    }

    // Cleanup simulations
    if (cpu_sim) |*sim| sim.deinit();
    if (gpu_sim) |*sim| sim.deinit();

    const deinit_check = gpa.deinit();
    if (deinit_check == .leak) {
        std.log.warn("Memory leak detected by GeneralPurposeAllocator!", .{});
        // Optionally, consider std.process.exit(1) if leaks are critical.
    }
}
