function("prepare_bazel_opts" "flags" "opts" "switch")
    string("STRIP" "${${flags}}" "${flags}")
    if (${flags})
        string("REGEX" "REPLACE" "[ ]+-" ";-" "${flags}" "${${flags}}")
        foreach ("OPT" "IN" "LISTS" "${flags}")
            if (${opts})
                string("REGEX" "REPLACE" "^([^ ]+)[ ]+\"?([^\"]+)\"?$" "\\1\\2" "OPT" "${OPT}")
                set("${opts}" "${${opts}};${switch}=${OPT}")
            else ()
                set("${opts}" "${switch}=${OPT}")
            endif ()
        endforeach ()
        set("${opts}" "${${opts}}" "PARENT_SCOPE")
    endif ()
endfunction()

vcpkg_from_github(
        "OUT_SOURCE_PATH" "SOURCE_PATH"
        "REPO" "ulfjack/ryu"
        "REF" "v2.0"
        "SHA512" "88a0cca74a4889e8e579987abdc75a6ac87c1cdae557e5a15c29dbfd65733f9e591d6569e97a9374444918475099087f8056e696a97c9be24e38eb737e2304c2"
        "HEAD_REF" "master"
)

find_program("BAZEL" "bazel" "PATHS" "${CURRENT_HOST_INSTALLED_DIR}/tools" "REQUIRED")
get_filename_component("BAZEL_DIR" "${BAZEL}" "DIRECTORY")
vcpkg_add_to_path("PREPEND" "${BAZEL_DIR}")
set("ENV{BAZEL_BIN_PATH}" "${BAZEL}")

vcpkg_cmake_get_vars("cmake_vars_file")
include("${cmake_vars_file}")
if (VCPKG_HOST_IS_WINDOWS)
    if (VCPKG_DETECTED_MSVC)
        set("ENV{BAZEL_VC}" "$ENV{VCInstallDir}")
    elseif (VCPKG_TARGET_IS_MINGW)
        if (NOT VCPKG_DETECTED_CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
            message("FATAL_ERROR" "RYU: ${TARGET_TRIPLET} is not supported on Windows!")
        endif ()
        set("BAZEL_COMPILER" "--compiler=mingw-gcc")
        # BAZEL_SH can be propagated to the build environment using VCPKG_KEEP_ENV_VARS
        if (NOT DEFINED "ENV{BAZEL_SH}")
            message("BAZEL_SH is not specified, trying to guess...")
            get_filename_component("DIR" ${VCPKG_DETECTED_CMAKE_C_COMPILER} "DIRECTORY")
            # Bazel expects Mingw-w64 to be installed in MSYS2 (pacman -S mingw-w64-x86_64-toolchain).
            # From BAZEL_SH it finds MSYS2 root, adds "mingw64" to the root and uses this path as the location of Mingw-w64.
            # It is also possible to use non-MSYS2 binaries with Bazel if they are installed to a directory
            # whose name ends with "mingw64", such as c:\mingw64 or c:\TDM-GCC-64\mingw64.
            string("REGEX" "REPLACE" "/mingw64/bin$" "" "MSYS2_ROOT" "${DIR}")
            string("REPLACE" "/" "\\" "MSYS2_ROOT" "${MSYS2_ROOT}")
            set("ENV{BAZEL_SH}" "${MSYS2_ROOT}\\usr\\bin\\bash.exe")
            message("BAZEL_SH $ENV{BAZEL_SH}")
        endif ()
    else ()
        message("FATAL_ERROR" "${TARGET_TRIPLET} is not supported!")
    endif ()
    if (VCPKG_DETECTED_CMAKE_SYSTEM_PROCESSOR STREQUAL "x86")
        set("BAZEL_CPU" "--cpu=x64_x86_windows")
    elseif (VCPKG_DETECTED_CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM")
        set("BAZEL_CPU" "--cpu=x64_arm_windows")
    elseif (VCPKG_DETECTED_CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM64")
        set("BAZEL_CPU" "--cpu=arm64_windows")
    endif ()
else ()
    set("ENV{CC}" "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
endif ()

prepare_bazel_opts("VCPKG_COMBINED_C_FLAGS_RELEASE" "CONLY_OPTS_RELEASE" "--conlyopt")
prepare_bazel_opts("VCPKG_COMBINED_C_FLAGS_DEBUG" "CONLY_OPTS_DEBUG" "--conlyopt")
prepare_bazel_opts("VCPKG_COMBINED_STATIC_LINKER_FLAGS_RELEASE" "LINK_OPTS_RELEASE" "--linkopt")
prepare_bazel_opts("VCPKG_COMBINED_STATIC_LINKER_FLAGS_DEBUG" "LINK_OPTS_DEBUG" "--linkopt")

if (VCPKG_HOST_IS_OSX)
    set("ENV{BAZEL_USE_CPP_ONLY_TOOLCHAIN}" "1")
    set("ENV{SDKROOT}" "${VCPKG_DETECTED_CMAKE_OSX_SYSROOT}")
    if (LINK_OPTS_RELEASE)
        set("LINK_OPTS_RELEASE" "${LINK_OPTS_RELEASE};")
    endif ()
    set("LINK_OPTS_RELEASE" "${LINK_OPTS_RELEASE}--linkopt=-L${VCPKG_DETECTED_CMAKE_OSX_SYSROOT}/usr/lib")
    if (LINK_OPTS_DEBUG)
        set("LINK_OPTS_DEBUG" "${LINK_OPTS_DEBUG};")
    endif ()
    set("LINK_OPTS_DEBUG" "${LINK_OPTS_DEBUG}--linkopt=-L${VCPKG_DETECTED_CMAKE_OSX_SYSROOT}/usr/lib")
endif ()

vcpkg_execute_build_process(
        "COMMAND" "${BAZEL}" "--batch" "build" "${BAZEL_COMPILER}" "${BAZEL_CPU}" ${CONLY_OPTS_RELEASE} ${LINK_OPTS_RELEASE} "--verbose_failures" "--strategy=CppCompile=standalone" "//ryu" "//ryu:ryu_printf"
        "WORKING_DIRECTORY" "${SOURCE_PATH}"
        "LOGNAME" "build-${TARGET_TRIPLET}-rel"
)

if (CMAKE_STATIC_LIBRARY_SUFFIX STREQUAL ".lib")
    file("INSTALL" "${SOURCE_PATH}/bazel-bin/ryu/ryu.lib" "DESTINATION" "${CURRENT_PACKAGES_DIR}/lib/")
    file("INSTALL" "${SOURCE_PATH}/bazel-bin/ryu/ryu_printf.lib" "DESTINATION" "${CURRENT_PACKAGES_DIR}/lib/")
else ()
    file("INSTALL" "${SOURCE_PATH}/bazel-bin/ryu/libryu.a" "DESTINATION" "${CURRENT_PACKAGES_DIR}/lib/")
    file("INSTALL" "${SOURCE_PATH}/bazel-bin/ryu/libryu_printf.a" "DESTINATION" "${CURRENT_PACKAGES_DIR}/lib/")
endif ()

vcpkg_execute_build_process(
        "COMMAND" "${BAZEL}" "--batch" "build" "${BAZEL_COMPILER}" "${BAZEL_CPU}" ${CONLY_OPTS_DEBUG} ${LINK_OPTS_DEBUG} "--verbose_failures" "--strategy=CppCompile=standalone" "//ryu" "//ryu:ryu_printf"
        "WORKING_DIRECTORY" "${SOURCE_PATH}"
        "LOGNAME" "build-${TARGET_TRIPLET}-dbg"
)

if (CMAKE_STATIC_LIBRARY_SUFFIX STREQUAL ".lib")
    file("INSTALL" "${SOURCE_PATH}/bazel-bin/ryu/ryu.lib" "DESTINATION" "${CURRENT_PACKAGES_DIR}/debug/lib/")
    file("INSTALL" "${SOURCE_PATH}/bazel-bin/ryu/ryu_printf.lib" "DESTINATION" "${CURRENT_PACKAGES_DIR}/debug/lib/")
else ()
    file("INSTALL" "${SOURCE_PATH}/bazel-bin/ryu/libryu.a" "DESTINATION" "${CURRENT_PACKAGES_DIR}/debug/lib/")
    file("INSTALL" "${SOURCE_PATH}/bazel-bin/ryu/libryu_printf.a" "DESTINATION" "${CURRENT_PACKAGES_DIR}/debug/lib/")
endif ()

file("INSTALL" "${SOURCE_PATH}/LICENSE-Boost" "DESTINATION" "${CURRENT_PACKAGES_DIR}/share/${PORT}" "RENAME" "copyright")
file("INSTALL" "${SOURCE_PATH}/ryu/ryu.h" "DESTINATION" "${CURRENT_PACKAGES_DIR}/include/ryu/")
file("INSTALL" "${SOURCE_PATH}/ryu/ryu2.h" "DESTINATION" "${CURRENT_PACKAGES_DIR}/include/ryu/")
file("INSTALL" "${CMAKE_CURRENT_LIST_DIR}/ryuConfig.cmake" "DESTINATION" "${CURRENT_PACKAGES_DIR}/share/${PORT}")
file("INSTALL" "${CMAKE_CURRENT_LIST_DIR}/usage" "DESTINATION" "${CURRENT_PACKAGES_DIR}/share/${PORT}")
