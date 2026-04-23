const std = @import("std");

// TODO: Add support for Windows and WebAssembly

// Flags used for defining C_FLAGS_STR and C_FLAGS_ARR
const C_RELEASE_FLAGS = "-O3 -ffast-math -flto";
const C_DEBUG_FLAGS = "-O0 -g";
var CMAKE_BUILD_TYPE: []const u8 = undefined;
var CMAKE_LTO: []const u8 = undefined;
const C_MARCH_NATIVE = "-march=native";

var C_FLAGS_STR: []u8 = undefined;
var C_FLAGS_ARR: []const []const u8 = undefined;

var IS_NATIVE_BUILD: bool = undefined;

var cwd = std.Io.Dir.cwd();

inline fn join(b: *std.Build, str_a: []const u8, str_b: []const u8) []u8 {
    return b.pathJoin(&[_][]const u8{ str_a, str_b });
}

inline fn path_join(b: *std.Build, str_a: []const u8, str_b: []const u8) std.Build.LazyPath {
    return b.path(join(b, str_a, str_b));
}

fn make_sdl(b: *std.Build, exe: *std.Build.Step.Compile, translate_c: *std.Build.Step.TranslateC, cpu_count: []const u8) *std.Build.Step {
    const sdl_src_dir = "external/SDL3";
    const sdl_build_dir = join(b, sdl_src_dir ++ "/build", CMAKE_BUILD_TYPE);

    const sdl_cmake_cmd = b.addSystemCommand(&.{
        "cmake",
        "-DSDL_AUDIO=OFF",
        "-DSDL_HAPTIC=OFF",
        "-DSDL_CAMERA=OFF",
        "-DSDL_SENSOR=OFF",
        "-DSDL_DIALOG=OFF",
        "-DSDL_JOYSTICK=OFF",
        "-DSDL_GPU=OFF",
        "-DSDL_RENDER=OFF",
        "-DSDL_POWER=OFF",
        "-DSDL_HIDAPI=OFF",
        "-DSDL_TRAY=OFF",
        b.fmt("-DCMAKE_BUILD_TYPE={s}", .{CMAKE_BUILD_TYPE}),
        b.fmt("-DCMAKE_INTERPROCEDURAL_OPTIMIZATION={s}", .{CMAKE_LTO}),
        b.fmt("-DCMAKE_C_FLAGS={s}", .{C_FLAGS_STR}),
        "-DSDL_SHARED=OFF",
        "-DSDL_STATIC=ON",
        "-DCMAKE_C_COMPILER=clang", // Has to be clang for lto to work between compilers since zig uses llvm, not sure how this works on windows
        "-DCMAKE_LINKER_TYPE=LLD",
        b.fmt("-B{s}", .{sdl_build_dir}),
        sdl_src_dir,
        "-G",
        "Ninja",
    });

    const sdl_make_cmd = b.addSystemCommand(&.{ "cmake", "--build", sdl_build_dir, "--config", CMAKE_BUILD_TYPE, "--", "-j", cpu_count });

    sdl_make_cmd.step.dependOn(&sdl_cmake_cmd.step);

    // exe.root_module.addIncludePath(b.path(sdl_src_dir ++ "/include"));

    translate_c.addIncludePath(b.path(sdl_src_dir ++ "/include"));
    exe.root_module.addObjectFile(path_join(b, sdl_build_dir, "libSDL3.a"));

    return &sdl_make_cmd.step;
}

fn make_wgpu_native(b: *std.Build, exe: *std.Build.Step.Compile, translate_c: *std.Build.Step.TranslateC, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    const wgpu_native_dir = "external/wgpu-native";
    const wgpu_native_cargo_toml = wgpu_native_dir ++ "/Cargo.toml";

    var wgpu_native_make_cmd: *std.Build.Step.Run = undefined;

    var rustflags: []const u8 = "-Zunstable-options -Cpanic=immediate-abort";
    if (IS_NATIVE_BUILD) {
        rustflags = b.fmt("{s} -Ctarget-cpu=native", .{rustflags});
    }

    // TODO: add rustflags for compiling this faster or optimizing
    if (optimize == .Debug) {
        wgpu_native_make_cmd = b.addSystemCommand(&.{ "cargo", "+nightly", "build", "--manifest-path", wgpu_native_cargo_toml, "--no-default-features", "--features=wgsl,vulkan", "-Zbuild-std=std,core,panic_abort", "-Zbuild-std-features=", "--target", "x86_64-unknown-linux-gnu" });
        wgpu_native_make_cmd.setEnvironmentVariable("RUSTFLAGS", rustflags);
        wgpu_native_make_cmd.setEnvironmentVariable("CARGO_PROFILE_DEBUG_PANIC", "abort");
        exe.root_module.addObjectFile(b.path(wgpu_native_dir ++ "/target/x86_64-unknown-linux-gnu/debug/libwgpu_native.a"));
    } else {
        rustflags = b.fmt("{s} -Zlocation-detail=none -Zfmt-debug=none", .{rustflags});

        wgpu_native_make_cmd = b.addSystemCommand(&.{ "cargo", "+nightly", "build", "--release", "--manifest-path", wgpu_native_cargo_toml, "--no-default-features", "--features=wgsl,vulkan" });

        wgpu_native_make_cmd.setEnvironmentVariable("RUSTFLAGS", rustflags);
        exe.root_module.addObjectFile(b.path(wgpu_native_dir ++ "/target/x86_64-unknown-linux-gnu/release/libwgpu_native.a"));
    }

    const ffi_dir = wgpu_native_dir ++ "/ffi";
    const webgpu_headers_dir = ffi_dir ++ "/webgpu";

    cwd.createDir(b.graph.io, webgpu_headers_dir, .default_dir) catch |err| {
        switch (err) {
            std.Io.Dir.CreateDirError.PathAlreadyExists => {},
            else => {
                std.debug.print("Error creating directory: {s}\n", .{webgpu_headers_dir});
                std.process.exit(1);
            },
        }
    };

    cwd.copyFile(ffi_dir ++ "/wgpu.h", cwd, webgpu_headers_dir ++ "/wgpu.h", b.graph.io, .{ .make_path = false, .permissions = .default_file, .replace = true }) catch {
        std.debug.print("Error copying wgpu.h file\n", .{});
        std.process.exit(1);
    };
    cwd.copyFile(ffi_dir ++ "/webgpu-headers/webgpu.h", cwd, webgpu_headers_dir ++ "/webgpu.h", b.graph.io, .{ .make_path = false, .permissions = .default_file, .replace = true }) catch {
        std.debug.print("Error copying webgpu.h file\n", .{});
        std.process.exit(1);
    };

    exe.root_module.addIncludePath(b.path(wgpu_native_dir ++ "/ffi"));
    translate_c.addIncludePath(b.path(wgpu_native_dir ++ "/ffi"));

    return &wgpu_native_make_cmd.step;
}

fn make_dawn(b: *std.Build, exe: *std.Build.Step.Compile, translate_c: *std.Build.Step.TranslateC, cpu_count: []const u8) *std.Build.Step {
    const dawn_src_dir = "external/dawn";
    const dawn_build_dir = join(b, dawn_src_dir ++ "/out", CMAKE_BUILD_TYPE);

    const fetch_dawn_deps_cmd = b.addSystemCommand(&.{
        "python3",
        dawn_src_dir ++ "/tools/fetch_dawn_dependencies.py",
        "--directory",
        dawn_src_dir,
        "--shallow",
    });

    const dawn_cmake_cmd = b.addSystemCommand(&.{
        "cmake",
        "-S",
        dawn_src_dir,
        "-B",
        dawn_build_dir,
        b.fmt("-DCMAKE_BUILD_TYPE={s}", .{CMAKE_BUILD_TYPE}),
        "-DCMAKE_C_COMPILER=clang",
        "-DCMAKE_CXX_COMPILER=clang++",
        "-DCMAKE_LINKER_TYPE=LLD",
        b.fmt("-DCMAKE_C_FLAGS={s}", .{C_FLAGS_STR}),
        b.fmt("-DCMAKE_CXX_FLAGS={s} -stdlib=libc++", .{C_FLAGS_STR}), // apparently needs to explicitly link against clang's libc++ for some reason
        b.fmt("-DCMAKE_INTERPROCEDURAL_OPTIMIZATION={s}", .{CMAKE_LTO}),

        "-DDAWN_BUILD_SAMPLES=OFF",
        "-DDAWN_BUILD_TESTS=OFF",
        "-DDAWN_BUILD_PROTOBUF=OFF",
        "-DDAWN_ENABLE_DESKTOP_GL=OFF",
        "-DDAWN_ENABLE_OPENGLES=OFF", // May need to change this for WebGL
        "-DDAWN_ENABLE_NULL=OFF",
        "-DDAWN_USE_GLFW=OFF",
        "-DDAWN_ENABLE_SPIRV_VALIDATION=OFF",
        "-DDAWN_DXC_ENABLE_ASSERTS_IN_NDEBUG=OFF",

        "-DTINT_BUILD_SPV_READER=OFF",
        "-DTINT_BUILD_GLSL_WRITER=OFF",
        "-DTINT_BUILD_GLSL_VALIDATOR=OFF",
        "-DTINT_BUILD_HLSL_WRITER=OFF",
        "-DTINT_BUILD_MSL_WRITER=OFF",
        "-DTINT_BUILD_SPV_WRITER=ON",
        "-DTINT_BUILD_WGSL_WRITER=OFF",
        "-DTINT_BUILD_IR_BINARY=OFF",
        "-DTINT_BUILD_TESTS=OFF",
        "-DTINT_BUILD_CMD_TOOLS=OFF",

        "-DBUILD_SHARED_LIBS=OFF",
        "-DDAWN_BUILD_MONOLITHIC_LIBRARY=STATIC",

        "-G",
        "Ninja",
    });

    dawn_cmake_cmd.step.dependOn(&fetch_dawn_deps_cmd.step);

    const dawn_make_cmd = b.addSystemCommand(&.{ "cmake", "--build", dawn_build_dir, "--config", CMAKE_BUILD_TYPE, "--", "-j", cpu_count });
    dawn_make_cmd.step.dependOn(&dawn_cmake_cmd.step);

    exe.root_module.addIncludePath(b.path(dawn_src_dir ++ "/include")); // for webgpu/webgpu.h
    exe.root_module.addIncludePath(path_join(b, dawn_build_dir, "gen/include")); // for dawn/webgpu.h
    translate_c.addIncludePath(b.path(dawn_src_dir ++ "/include"));
    translate_c.addIncludePath(path_join(b, dawn_build_dir, "gen/include"));

    exe.root_module.addObjectFile(path_join(b, dawn_build_dir, "/src/dawn/native/libwebgpu_dawn.a"));

    // TODO: see why we need to manually link against libc++ again
    exe.root_module.addObjectFile(.{ .cwd_relative = "/usr/lib/libc++.a" });

    return &dawn_make_cmd.step;
}

fn make_sdl3webgpu(b: *std.Build, exe: *std.Build.Step.Compile, translate_c: *std.Build.Step.TranslateC) void {
    exe.root_module.addIncludePath(b.path("external/sdl3webgpu"));
    translate_c.addIncludePath(b.path("external/sdl3webgpu"));
    exe.installHeadersDirectory(b.path("external/sdl3webgpu"), "sdl3webgpu", .{ .include_extensions = &.{"h"} });
    exe.root_module.addCSourceFile(.{ .file = b.path("external/sdl3webgpu/sdl3webgpu.c"), .flags = C_FLAGS_ARR, .language = .c });
}

fn make_imgui(b: *std.Build, exe: *std.Build.Step.Compile, translate_c: *std.Build.Step.TranslateC, optimize: std.builtin.OptimizeMode) void {
    const imgui_path = "external/imgui";

    // TODO: check if this is the right file
    exe.root_module.addCMacro("IMGUI_USER_CONFIG", "\"imgui_config.h\"");

    if (optimize != .Debug) {
        exe.root_module.addCMacro("IMGUI_DISABLE_DEBUG_TOOLS", "");
    }

    exe.root_module.addCSourceFiles(.{
        .root = b.path(imgui_path),
        .flags = C_FLAGS_ARR,
        .files = &[_][]const u8{
            "imgui.cpp",
            "imgui_demo.cpp",
            "imgui_draw.cpp",
            "imgui_tables.cpp",
            "imgui_widgets.cpp",
            "backends/imgui_impl_sdl3.cpp",
            "backends/imgui_impl_wgpu.cpp",
        },
        .language = .cpp,
    });

    exe.root_module.addIncludePath(b.path(imgui_path));
    exe.root_module.addIncludePath(b.path(imgui_path ++ "/backends"));
    translate_c.addIncludePath(b.path(imgui_path));
    translate_c.addIncludePath(b.path(imgui_path ++ "/backends"));
}

fn make_dear_bindings(b: *std.Build, exe: *std.Build.Step.Compile, translate_c: *std.Build.Step.TranslateC) *std.Build.Step {
    const dear_bindings_path = "external/dear_bindings";
    const dear_bindings_script = dear_bindings_path ++ "/dear_bindings.py";
    const venv_path = dear_bindings_path ++ "/.venv";
    const python_path = venv_path ++ "/bin/python3";
    const output_path = dear_bindings_path ++ "/generated";
    const backends_output_path = output_path ++ "/backends";
    const imgui_path = "external/imgui";
    const imgui_h_path = imgui_path ++ "/imgui.h";

    cwd.createDir(b.graph.io, backends_output_path, .default_dir) catch |err| {
        switch (err) {
            // TODO: make it so if it's already done, don't do it again
            std.Io.Dir.CreateDirError.PathAlreadyExists => {},
            else => {
                std.debug.print("Error creating directory: {s}\n", .{backends_output_path});
                std.process.exit(1);
            },
        }
    };

    const create_venv_cmd = b.addSystemCommand(&.{ "python3", "-m", "venv", venv_path });

    const install_python_deps_cmd = b.addSystemCommand(&.{ python_path, "-m", "pip", "install", "-r", dear_bindings_path ++ "/requirements.txt" });

    const gen_dcimgui_bindings = b.addSystemCommand(&.{ python_path, dear_bindings_script, "-o", output_path ++ "/dcimgui", imgui_h_path });

    const gen_sdl3_bindings = b.addSystemCommand(&.{ python_path, dear_bindings_script, "--backend", "--include", imgui_h_path, "--imconfig-path", "external/imgui_config/imgui_config.h", "-o", backends_output_path ++ "/dcimgui_impl_sdl3", imgui_path ++ "/backends/imgui_impl_sdl3.h" });

    const gen_wgpu_bindings = b.addSystemCommand(&.{ python_path, dear_bindings_script, "--backend", "--include", imgui_h_path, "--imconfig-path", "external/imgui_config/imgui_config.h", "-o", backends_output_path ++ "/dcimgui_impl_wgpu", imgui_path ++ "/backends/imgui_impl_wgpu.h" });

    install_python_deps_cmd.step.dependOn(&create_venv_cmd.step);
    gen_dcimgui_bindings.step.dependOn(&install_python_deps_cmd.step);
    gen_sdl3_bindings.step.dependOn(&install_python_deps_cmd.step);
    gen_wgpu_bindings.step.dependOn(&gen_sdl3_bindings.step);
    gen_wgpu_bindings.step.dependOn(&gen_dcimgui_bindings.step);

    exe.root_module.addIncludePath(b.path(output_path));
    exe.root_module.addIncludePath(b.path(backends_output_path));
    exe.root_module.addIncludePath(b.path("external/imgui_config"));

    translate_c.addIncludePath(b.path(output_path));
    translate_c.addIncludePath(b.path(backends_output_path));
    translate_c.addIncludePath(b.path("external/imgui_config"));

    // compile dcimgui.cpp
    exe.root_module.addCSourceFile(.{ .file = b.path(output_path ++ "/dcimgui.cpp"), .flags = C_FLAGS_ARR, .language = .cpp });
    // compile dcimgui_impl_sdl3.cpp
    exe.root_module.addCSourceFile(.{ .file = b.path(backends_output_path ++ "/dcimgui_impl_sdl3.cpp"), .flags = C_FLAGS_ARR, .language = .cpp });
    // compile dcimgui_impl_wgpu.cpp
    exe.root_module.addCSourceFile(.{ .file = b.path(backends_output_path ++ "/dcimgui_impl_wgpu.cpp"), .flags = C_FLAGS_ARR, .language = .cpp });

    return &gen_wgpu_bindings.step;
}

const WebGPUBackend = enum {
    dawn,
    @"wgpu-native",
};

// TODO: make downloading submodules parallel, see if adding something as a step is done in parallel or not
fn download_submodules(b: *std.Build, cpu_count: []const u8, webgpu_backend: WebGPUBackend) void {
    var recursive = std.process.spawn(
        b.graph.io,
        .{ .argv = &.{
            "git",
            "submodule",
            "update",
            "--init",
            "--recursive",
            "--recommend-shallow",
            "-j",
            cpu_count,
            "external/SDL3",
            "external/imgui",
            "external/dear_bindings",

            "external/sdl3webgpu",
        } },
    ) catch @panic("Couldn't spawn git process to download submodules...");

    _ = recursive.wait(b.graph.io) catch @panic("Couldn't download git submodules...");

    switch (webgpu_backend) {
        .dawn => {
            var webgpu_backend_cmd = std.process.spawn(
                b.graph.io,
                .{ .argv = &.{ "git", "submodule", "update", "--init", "--recommend-shallow", "-j", cpu_count, "external/dawn" } },
            ) catch @panic("Couldn't spawn git process to download submodules...");

            _ = webgpu_backend_cmd.wait(b.graph.io) catch @panic("Couldn't download git submodules...");
        },
        .@"wgpu-native" => {
            var webgpu_backend_cmd = std.process.spawn(
                b.graph.io,
                .{ .argv = &.{ "git", "submodule", "update", "--init", "--recommend-shallow", "-j", cpu_count, "external/wgpu-native" } },
            ) catch @panic("Couldn't spawn git process to download submodules...");
            _ = webgpu_backend_cmd.wait(b.graph.io) catch @panic("Couldn't download git submodules...");

            const wgpu_native_dir: std.process.Child.Cwd = .{ .path = "external/wgpu-native" };
            var wgpu_native_webgpu_headers_cmd = std.process.spawn(
                b.graph.io,
                .{ .argv = &.{ "git", "submodule", "update", "--init", "--recommend-shallow", "-j", cpu_count, "ffi/webgpu-headers" }, .cwd = wgpu_native_dir },
            ) catch @panic("Couldn't spawn git process to download submodules...");
            _ = wgpu_native_webgpu_headers_cmd.wait(b.graph.io) catch @panic("Couldn't download git submodules...");
        },
    }
}

// TODO: make this function more efficient by not running commands every time, and by doing things in parallel
fn make_deps(b: *std.Build, exe: *std.Build.Step.Compile, translate_c: *std.Build.Step.TranslateC, optimize: std.builtin.OptimizeMode) void {
    const cpu_count: usize = std.Thread.getCpuCount() catch 1;

    var buf: [2]u8 = undefined;
    const cpu_count_str = std.fmt.bufPrint(&buf, "{}", .{cpu_count}) catch "1";

    const webgpu_backend = b.option(WebGPUBackend, "webgpu-backend", "WebGPU Implementation to use: dawn or wgpu-native (default: wgpu-native)") orelse .@"wgpu-native";

    std.debug.print("Building with '{s}' webgpu backend.\nSee the '-Dwebgpu-backend' option for other values.\n\n", .{@tagName(webgpu_backend)});

    const make_deps_step = b.step("make-deps", "Make dependencies (SDL3, ImGui, Dawn, Wgpu-Native)");
    download_submodules(b, cpu_count_str, webgpu_backend);

    const sdl_make_step = make_sdl(b, exe, translate_c, cpu_count_str);
    make_deps_step.dependOn(sdl_make_step);

    make_imgui(b, exe, translate_c, optimize);
    make_sdl3webgpu(b, exe, translate_c);

    const make_dear_bindings_step = make_dear_bindings(b, exe, translate_c);
    make_deps_step.dependOn(make_dear_bindings_step);

    switch (webgpu_backend) {
        .@"wgpu-native" => {
            const wgpu_native_make_step = make_wgpu_native(b, exe, translate_c, optimize);
            make_deps_step.dependOn(wgpu_native_make_step);

            exe.root_module.addCMacro("IMGUI_IMPL_WEBGPU_BACKEND_WGPU", "");
        },
        .dawn => {
            const dawn_make_step = make_dawn(b, exe, translate_c, cpu_count_str);
            make_deps_step.dependOn(dawn_make_step);

            exe.root_module.addCMacro("IMGUI_IMPL_WEBGPU_BACKEND_DAWN", "");
        },
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    IS_NATIVE_BUILD = target.query.isNative();

    const optimize = b.standardOptimizeOption(.{});

    var c_flags: [:0]const u8 = undefined;
    if (optimize == .Debug) {
        c_flags = C_DEBUG_FLAGS;
        CMAKE_BUILD_TYPE = "Debug";
        CMAKE_LTO = "FALSE";
    } else {
        c_flags = C_RELEASE_FLAGS;
        CMAKE_BUILD_TYPE = "Release";
        CMAKE_LTO = "TRUE";
    }

    // Compile with -march=native when the zig build is also native
    if (IS_NATIVE_BUILD) {
        C_FLAGS_STR = b.fmt("{s} {s}", .{ c_flags, C_MARCH_NATIVE });
    } else {
        C_FLAGS_STR = @constCast(c_flags);
    }

    std.debug.print("C_FLAGS: {s}\n", .{C_FLAGS_STR});

    var parts = std.mem.splitScalar(u8, C_FLAGS_STR, ' ');
    var flags: std.ArrayList([]u8) = .empty;

    while (parts.next()) |part| {
        try flags.append(b.allocator, @constCast(part));
    }

    C_FLAGS_ARR = try flags.toOwnedSlice(b.allocator);

    const translate_c = b.addTranslateC(.{ .root_source_file = b.path("src/c.h"), .target = target, .optimize = optimize, .link_libc = true });
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
        // .unwind_tables = .none,
        .link_libc = true,
        .link_libcpp = true,
    });

    const exe = b.addExecutable(.{
        .name = "particle_simulation_2d",
        .root_module = exe_mod,
    });

    exe.lto = if (optimize != .Debug) .full else .none;

    make_deps(b, exe, translate_c, optimize);
    exe.root_module.addImport("c", translate_c.createModule());

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
