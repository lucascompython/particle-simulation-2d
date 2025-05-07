struct Particle {
    pos: vec2<f32>,
    _pad_pos: vec2<f32>,
    vel: vec2<f32>,
    _pad_vel: vec2<f32>,
    color: vec4<f32>,
    initial_color: vec4<f32>,
};

struct ProjectionUniforms {
    matrix: mat4x4<f32>,
};

@group(0) @binding(0) var<uniform> projection: ProjectionUniforms;

struct VertexInput {
    @location(0) pos: vec2<f32>,
    // _pad_pos is implicitly skipped by next attribute's offset
    @location(1) vel: vec2<f32>, // offset by 16 bytes (pos + _pad_pos)
    // _pad_vel implicitly skipped
    @location(2) color: vec4<f32>, // offset by 32 bytes (pos + _pad_pos + vel + _pad_vel)
    @location(3) initial_color: vec4<f32>, // offset by 48 bytes
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = projection.matrix * vec4<f32>(in.pos, 0.0, 1.0);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return in.color;
}