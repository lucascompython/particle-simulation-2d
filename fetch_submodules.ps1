$num_cpus = [Environment]::ProcessorCount

$j_arg = "-j$num_cpus"

git @("submodule", "update", "--init", "--recursive", "--recommend-shallow", $j_arg, "external/SDL3", "external/imgui", "external/wgpu-native", "external/dear_bindings", "external/sdl3webgpu")

git @("submodule", "update", "--init", "--recommend-shallow", $j_arg, "external/dawn")
