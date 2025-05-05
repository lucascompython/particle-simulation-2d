#!/bin/bash

set -xe

num_cpus=$(nproc)

git submodule update --init --recursive --recommend-shallow -j$num_cpus external/SDL3 external/imgui external/wgpu-native external/dear_bindings external/sdl3webgpu

git submodule update --init --recommend-shallow -j$num_cpus external/dawn
