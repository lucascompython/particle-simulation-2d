struct ProjectionUniforms {
    matrix: mat4x4<f32>,
};
@group(0) @binding(0) var<uniform> projection: ProjectionUniforms;

// Input attributes for each particle vertex.
// These @location decorators must match the shaderLocation
// in the WGPUVertexAttribute array in renderer_2d.zig.
struct VertexInput {
    @location(0) pos: vec2<f32>,     // from Particle.pos
    // @location(1) vel: vec2<f32>,  // from Particle.vel - uncomment if used
    @location(2) color: vec4<f32>, // from Particle.color
    // @location(3) initial_color: vec4<f32>, // from Particle.initial_color - uncomment if used
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = projection.matrix * vec4<f32>(in.pos, 0.0, 1.0);
    out.color = in.color; // Pass through the particle's color
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.color;
}