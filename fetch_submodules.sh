#!/bin/bash

set -xe


git submodule update --init --recursive --recommend-shallow -j$(nproc) external/SDL3 external/imgui external/wgpu-native external/dear_bindings external/sdl3webgpu

git submodule update --init --recommend-shallow -j$(nproc) external/dawn
