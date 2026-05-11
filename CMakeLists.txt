cmake_minimum_required(VERSION 3.16)

project(RayCastingCPU)

set(CMAKE_CXX_STANDARD 17)

find_package(SDL3 REQUIRED)

add_executable(RayCastingCPU RayCastingCPU.cpp)

target_link_libraries(RayCastingCPU PRIVATE SDL3::SDL3)