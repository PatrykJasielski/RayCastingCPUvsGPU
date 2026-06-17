cmake_minimum_required(VERSION 3.16)

project(RayCastingCPU LANGUAGES CXX CUDA)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CUDA_STANDARD 17)

find_package(SDL3 REQUIRED)
find_package(CUDAToolkit REQUIRED)

add_executable(RayCastingCPU RayCastingCPU.cpp)

target_link_libraries(RayCastingCPU PRIVATE SDL3::SDL3)

add_executable(RayCastingGPU RayCastingGPU.cu)

set_target_properties(RayCastingGPU PROPERTIES CUDA_SEPARABLE_COMPILATION ON)

target_link_libraries(RayCastingGPU PRIVATE SDL3::SDL3 CUDA::cudart)
