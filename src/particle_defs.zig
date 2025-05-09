const std = @import("std");

pub const Particle = extern struct {
    pos: [2]f32,
    _pad_pos: [2]f32, // For 16-byte alignment of struct elements for SSBO
    vel: [2]f32,
    _pad_vel: [2]f32, // For 16-byte alignment
    color: [4]f32, // RGBA
    initial_color: [4]f32, // To reset color or for specific modes

    pub fn init(pos_x: f32, pos_y: f32, vel_x: f32, vel_y: f32, r: f32, g: f32, b: f32, a: f32) Particle {
        return .{
            .pos = .{ pos_x, pos_y },
            ._pad_pos = .{ 0.0, 0.0 },
            .vel = .{ vel_x, vel_y },
            ._pad_vel = .{ 0.0, 0.0 },
            .color = .{ r, g, b, a },
            .initial_color = .{ r, g, b, a },
        };
    }
}; // Total size: 64 bytes

pub const SimParams = extern struct {
    delta_time: f32,
    mouse_force: f32,
    mouse_radius: f32,
    is_mouse_dragging: u32, // 0 (false) or 1 (true)

    damping: f32,
    particle_count: u32,
    canvas_width: f32,
    canvas_height: f32,

    mouse_pos_sim: [2]f32, // Mouse position in simulation coordinates
    _padding_simparams: [2]f32, // Ensure struct size is multiple of 16 bytes for UBO
}; // Total size: (8 * 4) = 32 + (2*4 + 2*4) = 16 = 48 bytes. std140 UBOs pad to 16B alignment.

pub const ProjectionUniforms = extern struct {
    matrix: [16]f32, // mat4x4
};

pub fn generate_initial_particles(allocator: std.mem.Allocator, count: u32, width: f32, height: f32) ![]Particle {
    var particles = try allocator.alloc(Particle, count);
    var rng = std.Random.DefaultPrng.init(0); // Seed for deterministic results

    for (0..count) |i| {
        const pos_x = rng.random().float(f32) * width;  // Random X within 0 to width
        const pos_y = rng.random().float(f32) * height; // Random Y within 0 to height

        const vel_x = (rng.random().float(f32) - 0.5) * 2.0; // Random velocity between -1 and 1
        const vel_y = (rng.random().float(f32) - 0.5) * 2.0;

        const r = rng.random().float(f32);
        const g = rng.random().float(f32);
        const b = rng.random().float(f32);

        particles[i] = Particle.init(pos_x, pos_y, vel_x, vel_y, r, g, b, 1.0);
    }
    return particles;
}
