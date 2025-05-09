const std = @import("std");
const c = @import("c.zig").c;

pub fn create_shader_module(device: *c.WGPUDeviceImpl, comptime label_comptime: ?[*:0]const u8, code_slice: [:0]const u8) c.WGPUShaderModule { // Return the optional pointer type
    const code_string_view = c.WGPUStringView{
        .data = code_slice.ptr,
        .length = code_slice.len,
    };

    // This structure will be part of the chain for WGPUShaderModuleDescriptor
    var wgsl_source_descriptor = c.WGPUShaderSourceWGSL{ // Corrected type
        .chain = .{ // This is the WGPUChainedStruct embedded in the WGSL descriptor
            .next = null,
            .sType = c.WGPUSType_ShaderSourceWGSL, // Identify this part of the chain
        },
        .code = code_string_view, // Assign the WGPUStringView as per compiler error
    };

    var label_string_view: c.WGPUStringView = .{ .data = null, .length = 0 };
    if (label_comptime) |lbl| {
        const label_slice = lbl[0..std.mem.len(lbl)];
        label_string_view = .{ .data = label_slice.ptr, .length = label_slice.len };
    }

    // This is the main descriptor
    const descriptor = c.WGPUShaderModuleDescriptor{ // This is the base descriptor
        .label = label_string_view,
        .nextInChain = &wgsl_source_descriptor.chain, // Point to the chain member of our WGSL descriptor
    };

    return c.wgpuDeviceCreateShaderModule(device, &descriptor);
}

// Orthographic projection matrix
// Maps coordinates from (left, right, bottom, top) to NDC (-1, 1)
// Zig math for mat4 would be useful here, or implement manually.
// For simplicity, this is a placeholder. A real implementation would use a math library or implement matrix ops.
pub fn create_orthographic_projection_matrix(
    left: f32,
    right: f32,
    bottom: f32,
    top: f32,
    near: f32,
    far: f32,
) [16]f32 {
    var m: [16]f32 = undefined;
    const lr = 1.0 / (left - right);
    const bt = 1.0 / (bottom - top);
    const nf = 1.0 / (near - far);

    m[0] = -2.0 * lr;
    m[1] = 0.0;
    m[2] = 0.0;
    m[3] = 0.0;

    m[4] = 0.0;
    m[5] = -2.0 * bt;
    m[6] = 0.0;
    m[7] = 0.0;

    m[8] = 0.0;
    m[9] = 0.0;
    m[10] = 2.0 * nf;
    m[11] = 0.0;

    m[12] = (left + right) * lr;
    m[13] = (top + bottom) * bt;
    m[14] = (far + near) * nf;
    m[15] = 1.0;

    return m;
}
