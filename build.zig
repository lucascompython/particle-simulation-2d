const std = @import("std");

const C_BASE_FLAGS = "-O3 -ffast-math -flto ";
const C_MARCH_NATIVE = "-march=native";

var C_FLAGS_STR: []u8 = undefined;
var C_FLAGS_ARR: []const []const u8 = undefined;

var IS_NATIVE_BUILD: bool = undefined;

fn make_sdl(b: *std.Build, exe: *std.Build.Step.Compile, cpu_count: []const u8) *std.Build.Step {
    const sdl_src_dir = "external/SDL3";
    const sdl_build_dir = sdl_src_dir ++ "/build";

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
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=TRUE",
        b.fmt("-DCMAKE_C_FLAGS={s}", .{C_FLAGS_STR}),
        "-DSDL_SHARED=OFF",
        "-DSDL_STATIC=ON",
        "-DCMAKE_C_COMPILER=clang", // Has to be clang for lto to work between compilers since zig uses llvm, not sure how this works on windows
        "-DCMAKE_LINKER_TYPE=LLD",
        "-B" ++ sdl_build_dir,
        sdl_src_dir,
        "-G",
        "Ninja",
    });

    const sdl_make_cmd = b.addSystemCommand(&.{ "cmake", "--build", sdl_build_dir, "--config", "Release", "--", "-j", cpu_count });

    sdl_make_cmd.step.dependOn(&sdl_cmake_cmd.step);

    exe.addIncludePath(b.path(sdl_src_dir ++ "/include"));

    exe.addObjectFile(b.path(sdl_build_dir ++ "/libSDL3.a"));

    return &sdl_make_cmd.step;
}

fn make_wgpu_native(b: *std.Build, exe: *std.Build.Step.Compile, optimize: std.builtin.OptimizeMode) *std.Build.Step {
    const wgpu_native_dir = "external/wgpu-native";

    var wgpu_native_make_cmd: *std.Build.Step.Run = undefined;

    const rustflags = if (IS_NATIVE_BUILD) "EXTRA_RUSTFLAGS=-Ctarget-cpu=native" else "";

    if (optimize == .Debug) {
        wgpu_native_make_cmd = b.addSystemCommand(&.{ "make", "lib-native", "-C", wgpu_native_dir, rustflags });
        exe.addObjectFile(b.path(wgpu_native_dir ++ "/target/debug/libwgpu_native.a"));
    } else {
        wgpu_native_make_cmd = b.addSystemCommand(&.{ "make", "lib-native-release", "-C", wgpu_native_dir, rustflags });
        exe.addObjectFile(b.path(wgpu_native_dir ++ "/target/x86_64-unknown-linux-gnu/release/libwgpu_native.a"));
    }

    exe.addIncludePath(b.path(wgpu_native_dir ++ "/ffi"));

    return &wgpu_native_make_cmd.step;
}

fn make_dawn(b: *std.Build, exe: *std.Build.Step.Compile, cpu_count: []const u8) *std.Build.Step {
    const dawn_src_dir = "external/dawn";
    const dawn_build_dir = dawn_src_dir ++ "/out/Release";

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
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_C_COMPILER=clang",
        "-DCMAKE_CXX_COMPILER=clang++",
        "-DCMAKE_LINKER_TYPE=LLD",
        b.fmt("-DCMAKE_C_FLAGS={s}", .{C_FLAGS_STR}),
        b.fmt("-DCMAKE_CXX_FLAGS={s} -stdlib=libc++", .{C_FLAGS_STR}), // apparently needs to explicitly link against clang's libc++ for some reason
        "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=TRUE",

        "-DDAWN_BUILD_SAMPLES=OFF",
        "-DDAWN_BUILD_TESTS=OFF",
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
        "-DTINT_BUILD_SPV_WRITER=OFF",
        "-DTINT_BUILD_WGSL_WRITER=OFF",
        "-DTINT_BUILD_TESTS=OFF",
        "-DTINT_BUILD_CMD_TOOLS=OFF",

        "-DBUILD_SHARED_LIBS=OFF",
        "-DDAWN_BUILD_MONOLITHIC_LIBRARY=OFF",

        "-G",
        "Ninja",
    });

    dawn_cmake_cmd.step.dependOn(&fetch_dawn_deps_cmd.step);

    const dawn_make_cmd = b.addSystemCommand(&.{ "cmake", "--build", dawn_build_dir, "--config", "Release", "--", "-j", cpu_count });
    dawn_make_cmd.step.dependOn(&dawn_cmake_cmd.step);

    exe.addIncludePath(b.path(dawn_src_dir ++ "/include")); // for webgpu/webgpu.h
    exe.addIncludePath(b.path(dawn_build_dir ++ "/gen/include")); // for dawn/webgpu.h

    exe.addObjectFile(b.path(dawn_build_dir ++ "/src/dawn/libdawn_proc.a"));

    exe.addObjectFile(b.path(dawn_build_dir ++ "/src/dawn/common/libdawn_common.a"));

    return &dawn_make_cmd.step;
}

fn make_sdl3webgpu(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.addIncludePath(b.path("external/sdl3webgpu"));
    exe.addCSourceFile(.{ .file = b.path("external/sdl3webgpu/sdl3webgpu.c"), .flags = C_FLAGS_ARR, .language = .c });
}

fn make_imgui(b: *std.Build, exe: *std.Build.Step.Compile, optimize: std.builtin.OptimizeMode) void {
    const imgui_path = "external/imgui";

    exe.root_module.addCMacro("IMGUI_USER_CONFIG", "\"imgui_config.h\"");

    if (optimize != .Debug) {
        exe.root_module.addCMacro("IMGUI_DISABLE_DEBUG_TOOLS", "");
    }

    exe.addCSourceFiles(.{
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

    exe.addIncludePath(b.path(imgui_path));
    exe.addIncludePath(b.path(imgui_path ++ "/backends"));
}

fn make_dear_bindings(b: *std.Build, exe: *std.Build.Step.Compile) *std.Build.Step {
    const dear_bindings_path = "external/dear_bindings";
    const venv_path = dear_bindings_path ++ "/.venv";
    const python_path = venv_path ++ "/bin/python3";
    const output_path = dear_bindings_path ++ "/generated";
    const backends_output_path = output_path ++ "/backends";
    const imgui_path = "external/imgui";

    std.fs.cwd().makePath(backends_output_path) catch {
        std.debug.print("Failed to create directory: {s}", .{backends_output_path});
        std.process.exit(1);
    };

    const create_venv_cmd = b.addSystemCommand(&.{ "python3", "-m", "venv", venv_path });

    const install_python_deps_cmd = b.addSystemCommand(&.{ python_path, "-m", "pip", "install", "-r", dear_bindings_path ++ "/requirements.txt" });

    const gen_dcimgui_bindings = b.addSystemCommand(&.{ python_path, dear_bindings_path ++ "/dear_bindings.py", "-o", output_path ++ "/dcimgui", imgui_path ++ "/imgui.h" });

    const gen_sdl3_bindings = b.addSystemCommand(&.{ python_path, dear_bindings_path ++ "/dear_bindings.py", "--backend", "--include", imgui_path ++ "/imgui.h", "--imconfig-path", "external/imgui_config/imgui_config.h", "-o", backends_output_path ++ "/dcimgui_impl_sdl3", imgui_path ++ "/backends/imgui_impl_sdl3.h" });

    const gen_wgpu_bindings = b.addSystemCommand(&.{ python_path, dear_bindings_path ++ "/dear_bindings.py", "--backend", "--include", imgui_path ++ "/imgui.h", "--imconfig-path", "external/imgui_config/imgui_config.h", "-o", backends_output_path ++ "/dcimgui_impl_wgpu", imgui_path ++ "/backends/imgui_impl_wgpu.h" });

    install_python_deps_cmd.step.dependOn(&create_venv_cmd.step);
    gen_dcimgui_bindings.step.dependOn(&install_python_deps_cmd.step);
    gen_sdl3_bindings.step.dependOn(&install_python_deps_cmd.step);
    gen_wgpu_bindings.step.dependOn(&gen_sdl3_bindings.step);
    gen_wgpu_bindings.step.dependOn(&gen_dcimgui_bindings.step);

    exe.addIncludePath(b.path(output_path));
    exe.addIncludePath(b.path(backends_output_path));
    exe.addIncludePath(b.path("external/imgui_config"));

    // compile dcimgui.cpp
    exe.addCSourceFile(.{ .file = b.path(output_path ++ "/dcimgui.cpp"), .flags = C_FLAGS_ARR, .language = .cpp });
    // compile dcimgui_impl_sdl3.cpp
    exe.addCSourceFile(.{ .file = b.path(backends_output_path ++ "/dcimgui_impl_sdl3.cpp"), .flags = C_FLAGS_ARR, .language = .cpp });
    // compile dcimgui_impl_wgpu.cpp
    exe.addCSourceFile(.{ .file = b.path(backends_output_path ++ "/dcimgui_impl_wgpu.cpp"), .flags = C_FLAGS_ARR, .language = .cpp });

    return &gen_wgpu_bindings.step;
}

const WebGPUBackend = enum {
    dawn,
    @"wgpu-native",
};

fn download_submodules(b: *std.Build, cpu_count: []const u8, webgpu_backend: WebGPUBackend) void {
    var recursive = std.process.Child.init(
        &.{
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
        },
        b.allocator,
    );

    _ = recursive.spawnAndWait() catch @panic("Couldn't download git submodules...");

    var webgpu_backend_cmd: std.process.Child = undefined;
    switch (webgpu_backend) {
        .dawn => {
            webgpu_backend_cmd = std.process.Child.init(
                &.{ "git", "submodule", "update", "--init", "--recommend-shallow", "-j", cpu_count, "external/dawn" },
                b.allocator,
            );
        },
        .@"wgpu-native" => {
            webgpu_backend_cmd = std.process.Child.init(
                &.{ "git", "submodule", "update", "--init", "--recursive", "--recommend-shallow", "-j", cpu_count, "external/wgpu-native" },
                b.allocator,
            );
        },
    }
    _ = webgpu_backend_cmd.spawnAndWait() catch @panic("Couldn't download git submodules...");
}

fn make_deps(b: *std.Build, exe: *std.Build.Step.Compile, optimize: std.builtin.OptimizeMode) void {
    const cpu_count: usize = std.Thread.getCpuCount() catch 1;

    var buf: [2]u8 = undefined;
    const cpu_count_str = std.fmt.bufPrint(&buf, "{}", .{cpu_count}) catch "1";

    const webgpu_backend = b.option(WebGPUBackend, "webgpu-backend", "WebGPU Implementation to use: dawn or wgpu-native (default: wgpu-native)") orelse .@"wgpu-native";

    std.debug.print("Building with '{s}' webgpu backend.\nSee the '-Dwebgpu-backend' option for other values.\n\n", .{@tagName(webgpu_backend)});

    const make_deps_step = b.step("make-deps", "Make dependencies (SDL3, ImGui, Dawn, Wgpu-Native)");
    download_submodules(b, cpu_count_str, webgpu_backend);

    const sdl_make_step = make_sdl(b, exe, cpu_count_str);
    make_deps_step.dependOn(sdl_make_step);

    make_imgui(b, exe, optimize);
    make_sdl3webgpu(b, exe);

    const make_dear_bindings_step = make_dear_bindings(b, exe);
    make_deps_step.dependOn(make_dear_bindings_step);

    switch (webgpu_backend) {
        .@"wgpu-native" => {
            const wgpu_native_make_step = make_wgpu_native(b, exe, optimize);
            make_deps_step.dependOn(wgpu_native_make_step);

            exe.root_module.addCMacro("IMGUI_IMPL_WEBGPU_BACKEND_WGPU", "");
        },
        .dawn => {
            const dawn_make_step = make_dawn(b, exe, cpu_count_str);
            make_deps_step.dependOn(dawn_make_step);

            exe.root_module.addCMacro("IMGUI_IMPL_WEBGPU_BACKEND_DAWN", "");
        },
    }
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    IS_NATIVE_BUILD = target.query.isNative();

    // Compile with -march=native when the zig build is also native
    if (IS_NATIVE_BUILD) {
        C_FLAGS_STR = try b.allocator.alloc(u8, C_BASE_FLAGS.len + C_MARCH_NATIVE.len);
        @memcpy(C_FLAGS_STR, C_BASE_FLAGS ++ C_MARCH_NATIVE);
    } else {
        C_FLAGS_STR = try b.allocator.alloc(u8, C_BASE_FLAGS.len);
        @memcpy(C_FLAGS_STR, C_BASE_FLAGS);
    }

    var parts = std.mem.splitScalar(u8, C_FLAGS_STR, ' ');
    var flags = std.ArrayList([]u8).init(b.allocator);

    while (parts.next()) |part| {
        try flags.append(@constCast(part));
    }

    C_FLAGS_ARR = try flags.toOwnedSlice();

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
        .unwind_tables = .none,
    });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "particle_simulation_2d",
        .root_module = exe_mod,
    });

    exe.want_lto = optimize != .Debug;

    exe.linkLibCpp(); // links by default to clang's libc++

    make_deps(b, exe, optimize);

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
