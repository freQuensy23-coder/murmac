cmake_minimum_required(VERSION 3.22)
project(murmur_llm C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MACOSX_RPATH ON)
set(CMAKE_INSTALL_RPATH "@loader_path")
set(CMAKE_BUILD_RPATH "@loader_path")

# Pinned commit lives in versions.env (single source of truth).
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/versions.env" _ver REGEX "^LLAMA_COMMIT=")
string(REGEX REPLACE "^LLAMA_COMMIT=\"?([0-9a-f]+)\"?.*" "\\1" MURMUR_LLAMA_COMMIT "${_ver}")
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/versions.env" _tag REGEX "^LLAMA_TAG=")
string(REGEX REPLACE "^LLAMA_TAG=\"?([A-Za-z0-9]+)\"?.*" "\\1" MURMUR_LLAMA_TAG "${_tag}")
file(STRINGS "${CMAKE_CURRENT_LIST_DIR}/versions.env" _sha REGEX "^LLAMA_ARCHIVE_SHA256=")
string(REGEX REPLACE "^LLAMA_ARCHIVE_SHA256=\"?([0-9a-f]+)\"?.*" "\\1" MURMUR_LLAMA_ARCHIVE_SHA256 "${_sha}")

set(MURMUR_LLAMA_SRC "" CACHE PATH "llama.cpp checkout at ${MURMUR_LLAMA_COMMIT} (empty = FetchContent)")
option(MURMUR_LLM_BENCH "build murmur-llm-bench" ON)
set(MURMUR_BUILD_VARIANT "macos-metal" CACHE STRING "Build variant name")

if (NOT MURMUR_LLAMA_SRC)
    include(FetchContent)
    FetchContent_Declare(llama_cpp
        URL      https://github.com/ggml-org/llama.cpp/archive/${MURMUR_LLAMA_COMMIT}.tar.gz
        URL_HASH SHA256=${MURMUR_LLAMA_ARCHIVE_SHA256}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    FetchContent_GetProperties(llama_cpp)
    if (NOT llama_cpp_POPULATED)
        FetchContent_Populate(llama_cpp)
    endif()
    set(MURMUR_LLAMA_SRC ${llama_cpp_SOURCE_DIR})
endif()

set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "")
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "")
set(LLAMA_BUILD_SERVER   OFF CACHE BOOL "")
set(LLAMA_BUILD_TOOLS    OFF CACHE BOOL "")
set(LLAMA_BUILD_COMMON   OFF CACHE BOOL "")
set(LLAMA_OPENSSL        OFF CACHE BOOL "")
set(GGML_METAL           ON  CACHE BOOL "")
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "")
set(GGML_BLAS            ON  CACHE BOOL "")
set(GGML_ACCELERATE      ON  CACHE BOOL "")
set(GGML_BACKEND_DL      ON  CACHE BOOL "")

if (NOT CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
endif()
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_LIBRARY_OUTPUT_DIRECTORY})

add_subdirectory(${MURMUR_LLAMA_SRC} llama.cpp)

add_library(murmur_llm SHARED src/murmur_llm.cpp include/murmur_llm.h)
target_include_directories(murmur_llm PUBLIC include)
target_link_libraries(murmur_llm PRIVATE llama ggml)
target_compile_definitions(murmur_llm PRIVATE
    MURMUR_LLAMA_TAG="${MURMUR_LLAMA_TAG}"
    MURMUR_LLAMA_COMMIT="${MURMUR_LLAMA_COMMIT}"
    MURMUR_BUILD_VARIANT="${MURMUR_BUILD_VARIANT}")
set_target_properties(murmur_llm PROPERTIES
    INSTALL_NAME_DIR "@rpath"
    BUILD_WITH_INSTALL_RPATH ON)

if (MURMUR_LLM_BENCH)
    add_executable(murmur-llm-bench src/murmur_llm_bench.cpp)
    target_link_libraries(murmur-llm-bench PRIVATE murmur_llm)
    set_target_properties(murmur-llm-bench PROPERTIES
        BUILD_WITH_INSTALL_RPATH ON
        INSTALL_RPATH "@executable_path")
endif()
