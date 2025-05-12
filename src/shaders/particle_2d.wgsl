struct ProjectionUniforms {
    matrix: mat4x4<f32>,
};
@group(0) @binding(0) var<uniform> projection: ProjectionUniforms;

// Input attributes for each particle vertex.
// These @location decorators must match the shaderLocation
// in the WGPUVertexAttribute array in renderer_2d.zig.
struct VertexInput {
    @location(0) pos: vec2<f32>,     // from Particle.pos
    @location(1) vel: vec2<f32>,     // from Particle.vel
    @location(2) color: vec4<f32>,   // from Particle.color
    // @location(3) initial_color: vec4<f32>, // from Particle.initial_color - uncomment if used
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) velocity: vec2<f32>, // Changed to vec2 to match input velocity
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = projection.matrix * vec4<f32>(in.pos, 0.0, 1.0);
    out.color = in.color; 
    out.velocity = in.vel; // Assign input velocity to output
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let speed = length(in.velocity);
    // Adjust the divisor (e.g., 5.0) to control how speed affects opacity.
    let opacity = clamp(speed / 5.0, 0.0, 1.0); 

    // The 'in.color.rgb' is already calculated based on speed by the compute/CPU sim.
    // We just modify its alpha component here based on speed.
    return vec4<f32>(in.color.rgb, opacity * in.color.a);
    // If in.color.a is always 1.0 from compute/CPU, this simplifies to:
    // return vec4<f32>(in.color.rgb, opacity);
}
