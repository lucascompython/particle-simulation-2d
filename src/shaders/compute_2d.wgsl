struct Particle {
    pos: vec2<f32>,
    _pad_pos: vec2<f32>,
    vel: vec2<f32>,
    _pad_vel: vec2<f32>,
    color: vec4<f32>,
    initial_color: vec4<f32>,
};

struct SimParams {
    delta_time: f32,
    mouse_force: f32,
    mouse_radius: f32,
    is_mouse_dragging: u32, // 0 or 1

    damping: f32,
    particle_count: u32,
    canvas_width: f32,
    canvas_height: f32,

    mouse_pos_sim: vec2<f32>,
    _padding_simparams: vec2<f32>,
};

@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(1) var<uniform> params: SimParams;

@compute @workgroup_size(256)
fn main_cs(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let index = global_id.x;
    if (index >= params.particle_count) {
        return;
    }

    var p = particles[index];

    // Apply mouse force
    if (params.is_mouse_dragging == 1u) {
        let diff = params.mouse_pos_sim - p.pos;
        let dist_sq = dot(diff, diff);
        let mouse_radius_sq = params.mouse_radius * params.mouse_radius;

        if (dist_sq < mouse_radius_sq && dist_sq > 1e-6) {
            let dist = sqrt(dist_sq);
            let force_factor = (1.0 - dist / params.mouse_radius); // Linear falloff
            let force_dir = diff / dist;
            
            p.vel += force_dir * params.mouse_force * force_factor * params.delta_time;
        }
    }

    // Update position
    p.pos += p.vel * params.delta_time;

    // Apply damping
    p.vel *= params.damping;

    // Boundary conditions (bounce off walls)
    if (p.pos.x < 0.0) {
        p.pos.x = 0.0;
        p.vel.x *= -1.0;
    } else if (p.pos.x > params.canvas_width) {
        p.pos.x = params.canvas_width;
        p.vel.x *= -1.0;
    }
    if (p.pos.y < 0.0) {
        p.pos.y = 0.0;
        p.vel.y *= -1.0;
    } else if (p.pos.y > params.canvas_height) {
        p.pos.y = params.canvas_height;
        p.vel.y *= -1.0;
    }
    
    // Example: Color by speed (can be more sophisticated)
    // let speed = length(p.vel);
    // let normalized_speed = clamp(speed / 10.0, 0.0, 1.0); 
    // p.color = vec4<f32>(normalized_speed, 1.0 - normalized_speed, 0.5, 1.0);

    particles[index] = p;
}