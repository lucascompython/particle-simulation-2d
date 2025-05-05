# 2D Particle Simulation
This project is built with [`Zig`](https://ziglang.org/), [`SDL3`](https://github.com/libsdl-org/SDL), [`Dawn`](https://github.com/google/dawn) / [`Wgpu-Native`](https://github.com/gfx-rs/wgpu-native) and [`ImGui`](https://github.com/ocornut/imgui).

This project is a rewrite of [this project](https://github.com/lucascompython/particles) that used Raylib and performed all the calculations on the CPU.

I'm making this project with the goal of learning modern graphics programming and the differences between graphics library stacks.

A 3D version of this simulation that uses [`Rust`](https://www.rust-lang.org/) + [`Winit`](https://github.com/rust-windowing/winit) + [`Wgpu`](https://github.com/gfx-rs/wgpu) + [`Egui`](https://github.com/emilk/egui), can be found [here](https://github.com/lucascompython/particle-simulation-3d).

## Simulation Methods
The simulation can run on different methods, such as:
- CPU - Works everywhere but has limited performance
- GPU (Compute Shaders) - Only works on native and WebGpu (no WebGl support) but has much better performance

I wanted to add another GPU method, namely Transform Feedback since it is (I think) pretty the most performant method for this simulation that can run on WebGl, but I've found it difficult to implement in `wgpu`. Here is a [discussion](https://github.com/gfx-rs/wgpu/discussions/7601) about it. Still looking into it!

## Build Locally

This project has the following build dependencies:
- `python3` - for [dear_bindings](https://github.com/dearimgui/dear_bindings)
- `git` - for downloading the [submodules](/external)
- `rust` - for compiling [wgpu-native](https://github.com/gfx-rs/wgpu-native)
- `clang` - for compiling C code with LTO enable and not conflict with Zig/Rust compilers
- `cmake` - for compiling [SDL3](https://github.com/libsdl-org/SDL)
- `ninja` - for compiling [SDL3](https://github.com/libsdl-org/SDL)

```bash
git clone --recurse-submodules --shallow-submodules -j$(nproc) https://github.com/lucascompython/particle-simulation-2d.git
cd particle-simulation-2d

zig build make-deps # Building dependencies (SDL3, ImGui, Dawn, Wgpu-Native)

zig build run
# OR
zig build run -Doptimize=ReleaseFast # for release build
```

## TODO:
- Add Web support
- Improve performance
- Add mobile support
- Make CI work nicely
