const std = @import("std");

fn make_sdl(b: *std.Build, exe: *std.Build.Step.Compile) *std.Build.Step {
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
        "-DCMAKE_C_FLAGS=-O3 -ffast-math",
        "-DSDL_SHARED=OFF",
        "-DSDL_STATIC=ON",
        "-DCMAKE_C_COMPILER=clang", // Has to be clang for lto to work between compilers since zig uses llvm, not sure how this works on windows
        "-B" ++ sdl_build_dir,
        sdl_src_dir,
    });

    const cpu_count = std.Thread.getCpuCount() catch 1;

    var buf: [2]u8 = undefined;
    const cpu_count_str = std.fmt.bufPrint(&buf, "{}", .{cpu_count}) catch "1";

    const sdl_make_cmd = b.addSystemCommand(&.{ "cmake", "--build", sdl_build_dir, "--config", "Release", "--", "-j", cpu_count_str });

    sdl_make_cmd.step.dependOn(&sdl_cmake_cmd.step);

    exe.addIncludePath(b.path(sdl_src_dir ++ "/include"));

    exe.addObjectFile(b.path(sdl_build_dir ++ "/libSDL3.a"));

    return &sdl_make_cmd.step;
}

fn make_wgpu_native(b: *std.Build, exe: *std.Build.Step.Compile) *std.Build.Step {
    const wgpu_native_dir = "external/wgpu-native";
    const wgpu_native_build_dir = wgpu_native_dir ++ "/target/x86_64-unknown-linux-gnu/release"; // TODO: Add support for other OS

    const wgpu_native_make_cmd = b.addSystemCommand(&.{ "make", "lib-native-release", "-C", wgpu_native_dir });

    exe.addIncludePath(b.path(wgpu_native_dir ++ "/ffi"));

    exe.addObjectFile(b.path(wgpu_native_build_dir ++ "/libwgpu_native.a"));

    return &wgpu_native_make_cmd.step;
}

fn make_sdl3webgpu(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.addIncludePath(b.path("external/sdl3webgpu"));
    exe.addCSourceFile(.{ .file = b.path("external/sdl3webgpu/sdl3webgpu.c"), .flags = &[_][]const u8{ "-O3", "-ffast-math", "-flto" }, .language = .c });
}

fn make_imgui(b: *std.Build, exe: *std.Build.Step.Compile, optimize: std.builtin.OptimizeMode) void {
    const imgui_path = "external/imgui";

    exe.root_module.addCMacro("IMGUI_IMPL_WEBGPU_BACKEND_WGPU", "");
    exe.root_module.addCMacro("IMGUI_USER_CONFIG", "\"imgui_config.h\"");

    if (optimize != .Debug) {
        exe.root_module.addCMacro("IMGUI_DISABLE_DEBUG_TOOLS", "");
    }

    exe.addCSourceFiles(.{ .root = b.path(imgui_path), .flags = &[_][]const u8{
        "-O3",
        "-ffast-math",
        "-flto",
    }, .files = &[_][]const u8{
        "imgui.cpp",
        "imgui_demo.cpp",
        "imgui_draw.cpp",
        "imgui_tables.cpp",
        "imgui_widgets.cpp",
        "backends/imgui_impl_sdl3.cpp",
        "backends/imgui_impl_wgpu.cpp",
    }, .language = .cpp });

    exe.addIncludePath(b.path(imgui_path));
    exe.addIncludePath(b.path(imgui_path ++ "/backends"));
}

fn make_dear_bindings(b: *std.Build, exe: *std.Build.Step.Compile) *std.Build.Step {
    const dear_bindings_path = "external/dear_bindings";
    const output_path = dear_bindings_path ++ "/generated";
    const backends_output_path = output_path ++ "/backends";
    const imgui_path = "external/imgui";

    std.fs.cwd().makePath(backends_output_path) catch {
        std.debug.print("Failed to create directory: {s}", .{backends_output_path});
        std.process.exit(1);
    };

    const install_python_deps_cmd = b.addSystemCommand(&.{ "python3", "-m", "pip", "install", "-r", dear_bindings_path ++ "/requirements.txt" });

    const gen_dcimgui_bindings = b.addSystemCommand(&.{ "python3", dear_bindings_path ++ "/dear_bindings.py", "-o", output_path ++ "/dcimgui", imgui_path ++ "/imgui.h" });

    const gen_sdl3_bindings = b.addSystemCommand(&.{ "python3", dear_bindings_path ++ "/dear_bindings.py", "--backend", "--include", imgui_path ++ "/imgui.h", "--imconfig-path", "external/imgui_config/imgui_config.h", "-o", backends_output_path ++ "/dcimgui_impl_sdl3", imgui_path ++ "/backends/imgui_impl_sdl3.h" });

    const gen_wgpu_bindings = b.addSystemCommand(&.{ "python3", dear_bindings_path ++ "/dear_bindings.py", "--backend", "--include", imgui_path ++ "/imgui.h", "--imconfig-path", "external/imgui_config/imgui_config.h", "-o", backends_output_path ++ "/dcimgui_impl_wgpu", imgui_path ++ "/backends/imgui_impl_wgpu.h" });

    gen_dcimgui_bindings.step.dependOn(&install_python_deps_cmd.step);
    gen_wgpu_bindings.step.dependOn(&gen_sdl3_bindings.step);
    gen_wgpu_bindings.step.dependOn(&gen_dcimgui_bindings.step);

    exe.addIncludePath(b.path(output_path));
    exe.addIncludePath(b.path(backends_output_path));
    exe.addIncludePath(b.path("external/imgui_config"));

    // compile dcimgui.cpp
    exe.addCSourceFile(.{ .file = b.path(output_path ++ "/dcimgui.cpp"), .flags = &.{ "-O3", "-ffast-math", "-lto" }, .language = .cpp });
    // compile dcimgui_impl_sdl3.cpp
    exe.addCSourceFile(.{ .file = b.path(backends_output_path ++ "/dcimgui_impl_sdl3.cpp"), .flags = &.{ "-O3", "-ffast-math", "-lto" }, .language = .cpp });
    // compile dcimgui_impl_wgpu.cpp
    exe.addCSourceFile(.{ .file = b.path(backends_output_path ++ "/dcimgui_impl_wgpu.cpp"), .flags = &.{ "-O3", "-ffast-math", "-lto" }, .language = .cpp });

    return &gen_wgpu_bindings.step;
}

fn make_deps(b: *std.Build, exe: *std.Build.Step.Compile, optimize: std.builtin.OptimizeMode) void {
    const sdl_make_step = make_sdl(b, exe);
    const wgpu_native_make_step = make_wgpu_native(b, exe);

    const make_dear_bindings_step = make_dear_bindings(b, exe);

    const make_deps_step = b.step("make-deps", "Make dependencies (SDL3, ImGui, Dawn, Wgpu-Native)");
    make_deps_step.dependOn(sdl_make_step);
    make_deps_step.dependOn(wgpu_native_make_step);
    make_imgui(b, exe, optimize);
    make_deps_step.dependOn(make_dear_bindings_step);
    make_sdl3webgpu(b, exe);
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

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

    exe.linkLibCpp();

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

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
