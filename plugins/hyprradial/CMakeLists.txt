cmake_minimum_required(VERSION 3.16)
project(hyprradial VERSION 0.0.1 LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(hyprland REQUIRED IMPORTED_TARGET hyprland)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(hyprradial SHARED hyprradial.cpp)
target_link_libraries(hyprradial PRIVATE PkgConfig::hyprland)

install(TARGETS hyprradial LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})