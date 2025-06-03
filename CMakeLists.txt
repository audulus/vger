cmake_minimum_required(VERSION 3.20)
project(vger LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 17)

# Paths
set(SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Sources/vger")
set(METAL_SRC "${SRC_DIR}/vger.metal")
set(AIR_FILE "${CMAKE_CURRENT_BINARY_DIR}/vger.air")
set(METALLIB_FILE "${CMAKE_CURRENT_BINARY_DIR}/vger.metallib")
set(METALLIB_OBJ "${CMAKE_CURRENT_BINARY_DIR}/vger_metallib.cpp")

# Collect source files (.cpp, .mm)
file(GLOB_RECURSE VGER_SOURCES
    "${SRC_DIR}/*.cpp"
    "${SRC_DIR}/*.mm"
)

# Step 1: Compile .metal to .air
add_custom_command(
    OUTPUT ${AIR_FILE}
    COMMAND xcrun -sdk macosx metal -c ${METAL_SRC} -o ${AIR_FILE}
    DEPENDS ${METAL_SRC}
    COMMENT "Compiling vger.metal to AIR"
)

# Step 2: Compile .air to .metallib
add_custom_command(
    OUTPUT ${METALLIB_FILE}
    COMMAND xcrun -sdk macosx metallib ${AIR_FILE} -o ${METALLIB_FILE}
    DEPENDS ${AIR_FILE}
    COMMENT "Linking AIR to METALLIB"
)

# Step 3: Convert .metallib to C array using xxd
add_custom_command(
    OUTPUT ${METALLIB_OBJ}
    COMMAND xxd -i ${METALLIB_FILE} > ${METALLIB_OBJ}
    DEPENDS ${METALLIB_FILE}
    COMMENT "Embedding metallib into C++ source"
)

# Custom target to ensure shader embedding is done first
add_custom_target(EmbedShader ALL DEPENDS ${METALLIB_OBJ})

# Step 4: Create dylib
add_library(vger SHARED
    ${VGER_SOURCES}
    ${METALLIB_OBJ}
)

add_dependencies(vger EmbedShader)

# Link necessary Apple frameworks
target_link_libraries(vger
    "-framework Foundation"
    "-framework Metal"
)

# Optional: Make it rpath-loadable
set_target_properties(vger PROPERTIES
    MACOSX_RPATH ON
    OUTPUT_NAME "vger"
    INSTALL_NAME_DIR "@rpath"
)

