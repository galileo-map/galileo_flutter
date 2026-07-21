# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "galileo_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# The Rust library is now built and bundled via Dart native assets
# (see hook/build.dart, using native_toolchain_rust) rather than here.
set(galileo_flutter_bundled_libraries
  PARENT_SCOPE
)
