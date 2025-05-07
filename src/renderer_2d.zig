const std = @import("std");
const c = @import("c.zig").c;
const particle_defs = @import("particle_defs.zig");
const utils = @import("utils.zig");

pub const ParticleRenderer = struct {
    render_pipeline: *c.WGPURenderPipelineImpl,
    projection_buffer: *c.WGPUBufferImpl,
    projection_bind_group_layout: *c.WGPUBindGroupLayoutImpl,
    projection_bind_group: *c.WGPUBindGroupImpl,
    shader_module: *c.WGPUShaderModuleImpl,

    pub fn init(
        allocator: std.mem.Allocator,
        device: *c.WGPUDeviceImpl, // Expect unwrapped *Impl type
        surface_format: c.WGPUTextureFormat,
    ) !ParticleRenderer {
        _ = allocator;
        const shader_code = @embedFile("shaders/particle_2d.wgsl");
        const shader_module = utils.create_shader_module(device, "Particle Shader", shader_code);

        const projection_buffer_label_str = "Projection Uniform Buffer";
        const projection_buffer_desc = c.WGPUBufferDescriptor{
            .label = .{ .data = projection_buffer_label_str.ptr, .length = projection_buffer_label_str.len },
            .size = @sizeOf(particle_defs.ProjectionUniforms),
            .usage = c.WGPUBufferUsage_Uniform | c.WGPUBufferUsage_CopyDst,
            .mappedAtCreation = 0,
        };
        const projection_buffer = c.wgpuDeviceCreateBuffer(device, &projection_buffer_desc);

        const projection_bgl_entry = c.WGPUBindGroupLayoutEntry{
            .binding = 0,
            .visibility = c.WGPUShaderStage_Vertex,
            .buffer = .{
                .type = c.WGPUBufferBindingType_Uniform,
                .hasDynamicOffset = 0,
                .minBindingSize = 0,
            },
            .sampler = .{}, // Not used
            .texture = .{}, // Not used
            .storageTexture = .{}, // Not used
        };
        const projection_bgl_label_str = "Projection Bind Group Layout";
        const projection_bgl_desc = c.WGPUBindGroupLayoutDescriptor{
            .label = .{ .data = projection_bgl_label_str.ptr, .length = projection_bgl_label_str.len },
            .entryCount = 1,
            .entries = &projection_bgl_entry,
        };
        const projection_bind_group_layout = c.wgpuDeviceCreateBindGroupLayout(device, &projection_bgl_desc);

        const projection_bg_entry = c.WGPUBindGroupEntry{
            .binding = 0,
            .buffer = projection_buffer,
            .offset = 0,
            .size = @sizeOf(particle_defs.ProjectionUniforms),
            .sampler = null, // Not used
            .textureView = null, // Not used
        };
        const projection_bg_label_str = "Projection Bind Group";
        const projection_bg_desc = c.WGPUBindGroupDescriptor{
            .label = .{ .data = projection_bg_label_str.ptr, .length = projection_bg_label_str.len },
            .layout = projection_bind_group_layout,
            .entryCount = 1,
            .entries = &projection_bg_entry,
        };
        const projection_bind_group = c.wgpuDeviceCreateBindGroup(device, &projection_bg_desc);

        const pipeline_layout_label_str = "Render Pipeline Layout";
        const pipeline_layout_desc = c.WGPUPipelineLayoutDescriptor{
            .label = .{ .data = pipeline_layout_label_str.ptr, .length = pipeline_layout_label_str.len },
            .bindGroupLayoutCount = 1,
            .bindGroupLayouts = &projection_bind_group_layout,
        };
        const pipeline_layout = c.wgpuDeviceCreatePipelineLayout(device, &pipeline_layout_desc);
        defer c.wgpuPipelineLayoutRelease(pipeline_layout); // Release layout when done

        const vertex_attributes = [_]c.WGPUVertexAttribute{
            .{ .format = c.WGPUVertexFormat_Float32x2, .offset = @offsetOf(particle_defs.Particle, "pos"), .shaderLocation = 0 }, // pos
            .{ .format = c.WGPUVertexFormat_Float32x2, .offset = @offsetOf(particle_defs.Particle, "vel"), .shaderLocation = 1 }, // vel
            .{ .format = c.WGPUVertexFormat_Float32x4, .offset = @offsetOf(particle_defs.Particle, "color"), .shaderLocation = 2 }, // color
            .{ .format = c.WGPUVertexFormat_Float32x4, .offset = @offsetOf(particle_defs.Particle, "initial_color"), .shaderLocation = 3 }, // initial_color
        };

        const vertex_buffer_layout = c.WGPUVertexBufferLayout{
            .arrayStride = @sizeOf(particle_defs.Particle),
            .stepMode = c.WGPUVertexStepMode_Instance, // Or Vertex if not instancing quads per particle
            .attributeCount = vertex_attributes.len,
            .attributes = &vertex_attributes,
        };
        // For point list, stepMode should be Vertex if particles are vertices.
        // If we are drawing instances, then Instance. Let's draw particle_count instances of a single point/quad.
        // The Rust example draws particle_count instances of 1 vertex (effectively points).
        // Let's use VertexStepMode_Vertex and draw particle_count vertices.
        // This means the vertex buffer is a list of Particle structs.

        // Define the blend state for alpha blending
        const alpha_blend_state = c.WGPUBlendState{
            .color = .{
                .operation = c.WGPUBlendOperation_Add,
                .srcFactor = c.WGPUBlendFactor_SrcAlpha,
                .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha,
            },
            .alpha = .{
                .operation = c.WGPUBlendOperation_Add,
                .srcFactor = c.WGPUBlendFactor_One, // Often ignored, but set for clarity
                .dstFactor = c.WGPUBlendFactor_Zero,
            },
        };

        const color_target_state = c.WGPUColorTargetState{
            .format = surface_format,
            .blend = &alpha_blend_state, // Use the defined struct
            .writeMask = c.WGPUColorWriteMask_All,
        };

        const fs_entry_point_str = "fs_main";
        const fragment_state = c.WGPUFragmentState{
            .module = shader_module.?, // Use unwrapped module
            .entryPoint = .{ .data = fs_entry_point_str.ptr, .length = fs_entry_point_str.len },
            .targetCount = 1,
            .targets = &color_target_state,
            .constantCount = 0, // zig v0.12
            .constants = null, // zig v0.12
        };

        const primitive_state = c.WGPUPrimitiveState{
            .topology = c.WGPUPrimitiveTopology_PointList,
            .stripIndexFormat = c.WGPUIndexFormat_Undefined,
            .frontFace = c.WGPUFrontFace_CCW,
            .cullMode = c.WGPUCullMode_None,
        };

        const vs_entry_point_str = "vs_main"; // Define string for vertex entry point
        const render_pipeline_desc = c.WGPURenderPipelineDescriptor{
            // Note: render_pipeline_desc_labeled below will set the actual pipeline label
            .label = .{ .data = null, .length = 0 }, // Temporary null label
            .layout = pipeline_layout,
            .vertex = .{
                .module = shader_module.?, // Use unwrapped module from previous fix
                .entryPoint = .{ .data = vs_entry_point_str.ptr, .length = vs_entry_point_str.len }, // Use StringView
                .bufferCount = 1,
                .buffers = &vertex_buffer_layout,
                .constantCount = 0, // zig v0.12
                .constants = null, // zig v0.12
            },
            .primitive = primitive_state,
            .depthStencil = null,
            .multisample = .{
                .count = 1,
                .mask = 0xFFFFFFFF,
                .alphaToCoverageEnabled = 0,
            },
            .fragment = &fragment_state,
        };
        const render_pipeline_label_str = "Particle Render Pipeline";
        var render_pipeline_desc_labeled = render_pipeline_desc; // Copy descriptor to add label
        render_pipeline_desc_labeled.label = .{ .data = render_pipeline_label_str.ptr, .length = render_pipeline_label_str.len };

        const render_pipeline = c.wgpuDeviceCreateRenderPipeline(device, &render_pipeline_desc_labeled);

        return .{
            .render_pipeline = render_pipeline.?,
            .projection_buffer = projection_buffer.?,
            .projection_bind_group_layout = projection_bind_group_layout.?,
            .projection_bind_group = projection_bind_group.?,
            .shader_module = shader_module.?,
        };
    }

    pub fn deinit(self: *ParticleRenderer) void {
        c.wgpuShaderModuleRelease(self.shader_module);
        c.wgpuBindGroupRelease(self.projection_bind_group);
        c.wgpuBindGroupLayoutRelease(self.projection_bind_group_layout);
        c.wgpuBufferRelease(self.projection_buffer);
        c.wgpuRenderPipelineRelease(self.render_pipeline);
    }

    pub fn render(
        self: *const ParticleRenderer,
        queue: *c.WGPUQueueImpl, // Expect unwrapped *Impl types
        encoder: *c.WGPUCommandEncoderImpl,
        target_view: *c.WGPUTextureViewImpl,
        particle_buffer: *c.WGPUBufferImpl,
        particle_count: u32,
        canvas_width: f32,
        canvas_height: f32,
    ) void {
        const proj_matrix = utils.create_orthographic_projection_matrix(0.0, canvas_width, canvas_height, 0.0, -1.0, 1.0);
        const uniforms = particle_defs.ProjectionUniforms{ .matrix = proj_matrix };
        c.wgpuQueueWriteBuffer(queue, self.projection_buffer, 0, &uniforms, @sizeOf(particle_defs.ProjectionUniforms));

        const render_pass_color_attachment = c.WGPURenderPassColorAttachment{
            .view = target_view,
            .resolveTarget = null,
            .loadOp = c.WGPULoadOp_Clear,
            .storeOp = c.WGPUStoreOp_Store,
            .clearValue = c.WGPUColor{ .r = 0.01, .g = 0.01, .b = 0.01, .a = 1.0 },
        };
        const render_pass_desc = c.WGPURenderPassDescriptor{
            .label = "Particle Render Pass",
            .colorAttachmentCount = 1,
            .colorAttachments = &render_pass_color_attachment,
            .depthStencilAttachment = null,
            .timestampWrites = null, // zig v0.12
        };

        const rpass = c.wgpuCommandEncoderBeginRenderPass(encoder, &render_pass_desc);
        defer c.wgpuRenderPassEncoderEnd(rpass);

        c.wgpuRenderPassEncoderSetPipeline(rpass, self.render_pipeline);
        c.wgpuRenderPassEncoderSetBindGroup(rpass, 0, self.projection_bind_group, 0, null);
        c.wgpuRenderPassEncoderSetVertexBuffer(rpass, 0, particle_buffer, 0, particle_count * @sizeOf(particle_defs.Particle));
        c.wgpuRenderPassEncoderDraw(rpass, particle_count, 1, 0, 0);
    }
};
