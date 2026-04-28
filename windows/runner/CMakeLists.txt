cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# winmm.lib provides timeBeginPeriod/timeEndPeriod — required to reduce the
# Windows default timer granularity from ~15.6 ms to 1 ms so that DWM VSync
# timestamps are precise enough that Flutter never sees them go backwards.
target_link_libraries(${BINARY_NAME} PRIVATE "winmm.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

find_program(CARGO_EXECUTABLE cargo REQUIRED)

add_custom_target(build_rust_core
  COMMAND
    ${CARGO_EXECUTABLE}
    build
    --release
    --manifest-path
    "${CMAKE_SOURCE_DIR}/../rust/Cargo.toml"
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/../rust"
  COMMENT "Building Rust core library (always release; debug Rust adds no value at runtime and would break flutter run -d windows)"
  VERBATIM
)

# Copy the freshly-built Rust DLL into the runner output dir so
# `flutter run -d windows` (and -d windows --release) both find it without
# manual intervention. The release CI pipeline still does its own copy step.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_SOURCE_DIR}/../rust/target/release/compact_games_core.dll"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/compact_games_core.dll"
  COMMENT "Staging compact_games_core.dll next to compact_games.exe"
  VERBATIM
)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
add_dependencies(${BINARY_NAME} build_rust_core)
