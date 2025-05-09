const std = @import("std");
const c = @import("c.zig").c;
const particle_defs = @import("particle_defs.zig");

pub const CpuSimulation = struct {
    allocator: std.mem.Allocator,
    particles: []particle_defs.Particle,
    particle_buffer: *c.WGPUBufferImpl, // Store unwrapped *Impl type
    particle_count: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        device: *c.WGPUDeviceImpl, // Expect unwrapped *Impl type
        initial_count: u32,
        canvas_width: f32,
        canvas_height: f32,
    ) !CpuSimulation {
        var self = CpuSimulation{
            .allocator = allocator,
            .particles = try particle_defs.generate_initial_particles(allocator, initial_count, canvas_width, canvas_height),
            .particle_buffer = undefined,
            .particle_count = initial_count,
        };

        const buffer_label_str = "CPU Particle Buffer";
        const buffer_desc = c.WGPUBufferDescriptor{
            .label = .{ .data = buffer_label_str.ptr, .length = buffer_label_str.len },
            .size = initial_count * @sizeOf(particle_defs.Particle),
            .usage = c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst,
            .mappedAtCreation = 0, // Use 0 for bool false
        };
        self.particle_buffer = c.wgpuDeviceCreateBuffer(device, &buffer_desc) orelse return error.BufferCreationFailed; // Or @panic
        c.wgpuQueueWriteBuffer(c.wgpuDeviceGetQueue(device), self.particle_buffer, 0, self.particles.ptr, self.particles.len * @sizeOf(particle_defs.Particle));

        return self;
    }

    pub fn deinit(self: *CpuSimulation) void {
        c.wgpuBufferRelease(self.particle_buffer);
        self.allocator.free(self.particles);
    }

    pub fn resize(
        self: *CpuSimulation,
        device: *c.WGPUDeviceImpl, // Expect unwrapped *Impl types
        queue: *c.WGPUQueueImpl,
        new_count: u32,
        canvas_width: f32,
        canvas_height: f32,
    ) !void {
        self.allocator.free(self.particles);
        self.particles = try particle_defs.generate_initial_particles(self.allocator, new_count, canvas_width, canvas_height);
        self.particle_count = new_count;

        c.wgpuBufferDestroy(self.particle_buffer); // Destroy old buffer
        c.wgpuBufferRelease(self.particle_buffer);

        const buffer_label_str = "CPU Particle Buffer (Resized)";
        const buffer_desc = c.WGPUBufferDescriptor{
            .label = .{ .data = buffer_label_str.ptr, .length = buffer_label_str.len },
            .size = new_count * @sizeOf(particle_defs.Particle),
            .usage = c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst,
            .mappedAtCreation = 0, // Use 0 for bool false
        };
        self.particle_buffer = c.wgpuDeviceCreateBuffer(device, &buffer_desc) orelse return error.BufferCreationFailed;
        c.wgpuQueueWriteBuffer(queue, self.particle_buffer, 0, self.particles.ptr, self.particles.len * @sizeOf(particle_defs.Particle));
    }

    pub fn update(self: *CpuSimulation, queue: *c.WGPUQueueImpl, params: *const particle_defs.SimParams) void {
        for (self.particles) |*p| {
            // Apply mouse force
            if (params.is_mouse_dragging == 1) {
                const dx = params.mouse_pos_sim[0] - p.pos[0];
                const dy = params.mouse_pos_sim[1] - p.pos[1];
                const dist_sq = dx * dx + dy * dy;
                const mouse_radius_sq = params.mouse_radius * params.mouse_radius;

                if (dist_sq < mouse_radius_sq and dist_sq > 1e-6) {
                    const dist = @sqrt(dist_sq);
                    const force_factor = (1.0 - dist / params.mouse_radius); // Linear falloff
                    const force_x = (dx / dist) * params.mouse_force * force_factor;
                    const force_y = (dy / dist) * params.mouse_force * force_factor;

                    p.vel[0] += force_x * params.delta_time;
                    p.vel[1] += force_y * params.delta_time;
                }
            }

            // Update position
            p.pos[0] += p.vel[0] * params.delta_time;
            p.pos[1] += p.vel[1] * params.delta_time;

            // Apply damping
            p.vel[0] *= params.damping;
            p.vel[1] *= params.damping;

            // Boundary conditions (bounce off walls)
            if (p.pos[0] < 0) {
                p.pos[0] = 0;
                p.vel[0] *= -1.0;
            } else if (p.pos[0] > params.canvas_width) {
                p.pos[0] = params.canvas_width;
                p.vel[0] *= -1.0;
            }
            if (p.pos[1] < 0) {
                p.pos[1] = 0;
                p.vel[1] *= -1.0;
            } else if (p.pos[1] > params.canvas_height) {
                p.pos[1] = params.canvas_height;
                p.vel[1] *= -1.0;
            }

            // Example: Color by speed
            // const speed_sq = p.vel[0]*p.vel[0] + p.vel[1]*p.vel[1];
            // const normalized_speed = @sqrt(speed_sq) / 10.0; // Normalize based on typical max speed
            // p.color[0] = @floatClamp(normalized_speed, 0.0, 1.0);
            // p.color[1] = @floatClamp(1.0 - normalized_speed, 0.0, 1.0);
            // p.color[2] = 0.5; // Some base blue
        }
        c.wgpuQueueWriteBuffer(queue, self.particle_buffer, 0, self.particles.ptr, self.particles.len * @sizeOf(particle_defs.Particle));
    }
};
