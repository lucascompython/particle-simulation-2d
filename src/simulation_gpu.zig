const std = @import("std");
const c = @import("c.zig").c;
const particle_defs = @import("particle_defs.zig");
const utils = @import("utils.zig");

pub const GpuSimulation = struct {
    allocator: std.mem.Allocator,
    particle_buffer: *c.WGPUBufferImpl, // Store unwrapped *Impl types
    sim_param_buffer: *c.WGPUBufferImpl,
    compute_pipeline: *c.WGPUComputePipelineImpl,
    bind_group_layout: *c.WGPUBindGroupLayoutImpl,
    bind_group: ?*c.WGPUBindGroupImpl, // Make this optional
    particle_count: u32,
    shader_module: c.WGPUShaderModule, // Store optional pointer

    pub fn init(
        allocator: std.mem.Allocator,
        device: *c.WGPUDeviceImpl, // Expect unwrapped *Impl type
        initial_count: u32,
        canvas_width: f32,
        canvas_height: f32,
    ) !GpuSimulation {
        var self = GpuSimulation{
            .allocator = allocator,
            .particle_buffer = undefined,
            .sim_param_buffer = undefined,
            .compute_pipeline = undefined,
            .bind_group_layout = undefined,
            .bind_group = null, // Initialize as null
            .particle_count = initial_count,
            .shader_module = undefined,
        };

        // Create particle buffer
        const initial_particles = try particle_defs.generate_initial_particles(allocator, initial_count, canvas_width, canvas_height);
        defer allocator.free(initial_particles);

        const particle_buffer_label_str = "GPU Particle Buffer";
        const particle_buffer_desc = c.WGPUBufferDescriptor{
            .label = .{ .data = particle_buffer_label_str.ptr, .length = particle_buffer_label_str.len },
            .size = initial_count * @sizeOf(particle_defs.Particle),
            .usage = c.WGPUBufferUsage_Storage | c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst,
            .mappedAtCreation = 0, // Use 0 for bool false
        };
        self.particle_buffer = c.wgpuDeviceCreateBuffer(device, &particle_buffer_desc) orelse return error.BufferCreationFailed;
        c.wgpuQueueWriteBuffer(c.wgpuDeviceGetQueue(device), self.particle_buffer, 0, initial_particles.ptr, initial_particles.len * @sizeOf(particle_defs.Particle));

        // Create sim_param_buffer
        const sim_param_buffer_label_str = "Sim Param Buffer";
        const sim_param_buffer_desc = c.WGPUBufferDescriptor{
            .label = .{ .data = sim_param_buffer_label_str.ptr, .length = sim_param_buffer_label_str.len },
            .size = @sizeOf(particle_defs.SimParams),
            .usage = c.WGPUBufferUsage_Uniform | c.WGPUBufferUsage_CopyDst,
            .mappedAtCreation = 0, // Use 0 for bool false
        };
        self.sim_param_buffer = c.wgpuDeviceCreateBuffer(device, &sim_param_buffer_desc) orelse return error.BufferCreationFailed;

        // Shader
        const shader_code = @embedFile("shaders/compute_2d.wgsl");
        self.shader_module = utils.create_shader_module(device, "Compute Shader", shader_code);

        // Bind Group Layout
        const bgl_entries = [_]c.WGPUBindGroupLayoutEntry{
            .{ // Particle Buffer
                .binding = 0,
                .visibility = c.WGPUShaderStage_Compute,
                .buffer = .{ .type = c.WGPUBufferBindingType_Storage, .hasDynamicOffset = 0, .minBindingSize = 0 },
                .sampler = .{},
                .texture = .{},
                .storageTexture = .{},
            },
            .{ // SimParams Buffer
                .binding = 1,
                .visibility = c.WGPUShaderStage_Compute,
                .buffer = .{ .type = c.WGPUBufferBindingType_Uniform, .hasDynamicOffset = 0, .minBindingSize = 0 },
                .sampler = .{},
                .texture = .{},
                .storageTexture = .{},
            },
        };
        const bgl_label_str = "Compute Bind Group Layout";
        const bgl_desc = c.WGPUBindGroupLayoutDescriptor{
            .label = .{ .data = bgl_label_str.ptr, .length = bgl_label_str.len },
            .entryCount = bgl_entries.len,
            .entries = &bgl_entries,
        };
        self.bind_group_layout = c.wgpuDeviceCreateBindGroupLayout(device, &bgl_desc).?;

        // Bind Group
        try self.recreate_bind_group(device); // Call helper to create/recreate bind group
        if (self.bind_group == null) { // Check if bind group creation was successful
            std.log.err("Failed to create initial bind group", .{});
            return error.BindGroupCreationFailed;
        }

        // Pipeline
        const pipeline_layout_label_str = "Compute Pipeline Layout";
        const pipeline_layout_desc = c.WGPUPipelineLayoutDescriptor{
            .label = .{ .data = pipeline_layout_label_str.ptr, .length = pipeline_layout_label_str.len },
            .bindGroupLayoutCount = 1,
            .bindGroupLayouts = &self.bind_group_layout,
        };
        const pipeline_layout = c.wgpuDeviceCreatePipelineLayout(device, &pipeline_layout_desc);

        const compute_pipeline_label_str = "Compute Pipeline";
        const cs_entry_point_str = "main_cs";
        const compute_pipeline_desc = c.WGPUComputePipelineDescriptor{
            .label = .{ .data = compute_pipeline_label_str.ptr, .length = compute_pipeline_label_str.len },
            .layout = pipeline_layout,
            .compute = .{
                .module = self.shader_module.?, // Use unwrapped shader module
                .entryPoint = .{ .data = cs_entry_point_str.ptr, .length = cs_entry_point_str.len },
                .constantCount = 0,
                .constants = null,
            },
        };
        self.compute_pipeline = c.wgpuDeviceCreateComputePipeline(device, &compute_pipeline_desc).?;
        c.wgpuPipelineLayoutRelease(pipeline_layout);

        return self;
    }

    fn recreate_bind_group(self: *GpuSimulation, device: *c.WGPUDeviceImpl) !void {
        if (self.bind_group) |bg_to_release| {
            c.wgpuBindGroupRelease(bg_to_release);
        }
        const bg_entries = [_]c.WGPUBindGroupEntry{
            .{ .binding = 0, .buffer = self.particle_buffer, .offset = 0, .size = self.particle_count * @sizeOf(particle_defs.Particle) },
            .{ .binding = 1, .buffer = self.sim_param_buffer, .offset = 0, .size = @sizeOf(particle_defs.SimParams) },
        };
        const bg_label_str = "Compute Bind Group";
        const bg_desc = c.WGPUBindGroupDescriptor{
            .label = .{ .data = bg_label_str.ptr, .length = bg_label_str.len },
            .layout = self.bind_group_layout,
            .entryCount = bg_entries.len,
            .entries = &bg_entries,
        };
        self.bind_group = c.wgpuDeviceCreateBindGroup(device, &bg_desc);
        if (self.bind_group == null) {
            return error.BindGroupCreationFailed;
        }
    }

    pub fn deinit(self: *GpuSimulation) void {
        c.wgpuComputePipelineRelease(self.compute_pipeline);
        if (self.bind_group) |bg| c.wgpuBindGroupRelease(bg);
        c.wgpuBindGroupLayoutRelease(self.bind_group_layout);
        c.wgpuShaderModuleRelease(self.shader_module);
        c.wgpuBufferRelease(self.sim_param_buffer);
        c.wgpuBufferRelease(self.particle_buffer);
    }

    pub fn resize(
        self: *GpuSimulation,
        device: *c.WGPUDeviceImpl, // Expect unwrapped *Impl types
        queue: *c.WGPUQueueImpl,
        new_count: u32,
        canvas_width: f32,
        canvas_height: f32,
    ) !void {
        const new_particles = try particle_defs.generate_initial_particles(self.allocator, new_count, canvas_width, canvas_height);
        defer self.allocator.free(new_particles);

        c.wgpuBufferDestroy(self.particle_buffer);
        c.wgpuBufferRelease(self.particle_buffer);

        const particle_buffer_label_str = "GPU Particle Buffer (Resized)";
        const particle_buffer_desc = c.WGPUBufferDescriptor{
            .label = .{ .data = particle_buffer_label_str.ptr, .length = particle_buffer_label_str.len },
            .size = new_count * @sizeOf(particle_defs.Particle),
            .usage = c.WGPUBufferUsage_Storage | c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst,
            .mappedAtCreation = 0, // Use 0 for bool false
        };
        self.particle_buffer = c.wgpuDeviceCreateBuffer(device, &particle_buffer_desc) orelse return error.BufferCreationFailed;
        c.wgpuQueueWriteBuffer(queue, self.particle_buffer, 0, new_particles.ptr, new_particles.len * @sizeOf(particle_defs.Particle));

        self.particle_count = new_count;
        try self.recreate_bind_group(device);
    }

    pub fn update(self: *GpuSimulation, queue: *c.WGPUQueueImpl, encoder: *c.WGPUCommandEncoderImpl, params: *const particle_defs.SimParams) void {
        c.wgpuQueueWriteBuffer(queue, self.sim_param_buffer, 0, params, @sizeOf(particle_defs.SimParams));

        const compute_pass_label_str = "Particle Compute Pass";
        const compute_pass_desc = c.WGPUComputePassDescriptor{ .label = .{ .data = compute_pass_label_str.ptr, .length = compute_pass_label_str.len }, .timestampWrites = null };
        const cpass = c.wgpuCommandEncoderBeginComputePass(encoder, &compute_pass_desc);
        defer c.wgpuComputePassEncoderEnd(cpass);

        c.wgpuComputePassEncoderSetPipeline(cpass, self.compute_pipeline);
        c.wgpuComputePassEncoderSetBindGroup(cpass, 0, self.bind_group.?, 0, null); // Unwrap optional

        const workgroup_size = 256; // Must match shader
        const workgroup_count_x = (self.particle_count + workgroup_size - 1) / workgroup_size;
        c.wgpuComputePassEncoderDispatchWorkgroups(cpass, workgroup_count_x, 1, 1);
    }
};
