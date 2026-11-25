cmake_minimum_required(VERSION 3.22)
project(bsi_ncnn LANGUAGES CXX)

include(FetchContent)
if(ANDROID_ABI STREQUAL "x86_64" OR ANDROID_ABI STREQUAL "x86")
    # The upstream Android x86 SDK uses AVX instructions even in its FP32 CPU
    # path. Some Android emulators and other x86 targets lack OS-enabled AVX.
    set(NCNN_AVX OFF CACHE BOOL "" FORCE)
    set(NCNN_AVX2 OFF CACHE BOOL "" FORCE)
    set(NCNN_RUNTIME_CPU OFF CACHE BOOL "" FORCE)
    set(NCNN_VULKAN ON CACHE BOOL "" FORCE)
    set(NCNN_SHARED_LIB ON CACHE BOOL "" FORCE)
    set(NCNN_BUILD_BENCHMARK OFF CACHE BOOL "" FORCE)
    set(NCNN_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(NCNN_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
    set(NCNN_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(
        ncnn_source
        URL https://github.com/Tencent/ncnn/releases/download/20261020/ncnn-20261020-full-source.zip
        URL_HASH SHA256=699d9acc67489eee0993a551ca1ebc247bbf0f4e33babe1dec810e6a9a52b988
    )
    FetchContent_MakeAvailable(ncnn_source)
else()
    FetchContent_Declare(
        ncnn_android
        URL https://github.com/Tencent/ncnn/releases/download/20261020/ncnn-20261020-android-vulkan-shared.zip
        URL_HASH SHA256=1b01048590564bae1c3d2d2a2b37ff101d50ad86c2cd2dc862bce7087905444d
    )
    FetchContent_GetProperties(ncnn_android)
    if(NOT ncnn_android_POPULATED)
        FetchContent_Populate(ncnn_android)
    endif()

    set(ncnn_sdk "${ncnn_android_SOURCE_DIR}/${ANDROID_ABI}")
    add_library(ncnn SHARED IMPORTED)
    set_target_properties(ncnn PROPERTIES
        IMPORTED_LOCATION "${ncnn_sdk}/lib/libncnn.so"
        INTERFACE_INCLUDE_DIRECTORIES "${ncnn_sdk}/include/ncnn"
    )
endif()
add_library(bsi_ncnn SHARED ../../../../../native/ncnn_bridge.cpp)
target_compile_features(bsi_ncnn PRIVATE cxx_std_17)
target_compile_options(bsi_ncnn PRIVATE -fexceptions -fvisibility=hidden)
target_link_libraries(bsi_ncnn PRIVATE ncnn log android)
target_link_options(bsi_ncnn PRIVATE "-Wl,-z,max-page-size=16384")
