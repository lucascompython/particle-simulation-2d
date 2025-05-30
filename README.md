# 2D Particle Simulation
This project is built with [`Zig`](https://ziglang.org/), [`SDL3`](https://github.com/libsdl-org/SDL), [`Dawn`](https://github.com/google/dawn) / [`Wgpu-Native`](https://github.com/gfx-rs/wgpu-native) and [`ImGui`](https://github.com/ocornut/imgui).

This project is a rewrite of [this project](https://github.com/lucascompython/particles) that used Raylib and performed all the calculations on the CPU.

I'm making this project with the goal of learning modern graphics programming and the differences between graphics library stacks.

A 3D version of this simulation that uses [`Rust`](https://www.rust-lang.org/) + [`Winit`](https://github.com/rust-windowing/winit) + [`Wgpu`](https://github.com/gfx-rs/wgpu) + [`Egui`](https://github.com/emilk/egui), can be found [here](https://github.com/lucascompython/particle-simulation-3d).

## Demo
https://github.com/user-attachments/assets/5b5efdc1-bf9a-4533-bed4-976d08e197d7



## Simulation Methods
The simulation can run on different methods, such as:
- CPU - Works everywhere but has limited performance
- GPU (Compute Shaders) - Only works on native and WebGPU (no WebGL support) but has much better performance

I wanted to add another GPU method, namely Transform Feedback since it is (I think) pretty the most performant method for this simulation that can run on WebGL, but I've found it difficult to implement in `wgpu`. Here is a [discussion](https://github.com/gfx-rs/wgpu/discussions/7601) about it. Still looking into it!

## Build Locally

This project has the following build dependencies:
- **zig** - for, well, the program itself
- **python3** - for [`dear_bindings`](https://github.com/dearimgui/dear_bindings) and [`fetching the dependencies of Dawn`](https://github.com/google/dawn/blob/main/tools/fetch_dawn_dependencies.py)
- **git** - for downloading the [submodules](/external)
- **rust** - for compiling `wgpu-native`
- **clang** - for compiling `C`/`C++` code with `LTO` enabled and not conflict with the `Zig`/`Rust` compilers
- **cmake** - for compiling `SDL3` and `Dawn`
- **ninja** - for compiling `SDL3` and `Dawn`
- And development packages of multiple things like OpenGL, X11, Wayland, libc++, etc.

```bash
git clone https://github.com/lucascompython/particle-simulation-2d.git
cd particle-simulation-2d

zig build make-deps # Will fetch the submodules and build the dependencies (SDL3, ImGui, Dawn, Wgpu-Native)

zig build run
# OR
zig build run -Doptimize=ReleaseFast # for release build
```

## TODO:
- Add Web support
- Improve performance
- Add mobile support
- Make CI work nicely
