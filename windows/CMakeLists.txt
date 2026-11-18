# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(local_convert LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "local_convert")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Empaquetado automático de FFmpeg (Windows x64) ===
set(FFMPEG_CACHE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.cache/ffmpeg")
set(FFMPEG_EXE "${FFMPEG_CACHE_DIR}/ffmpeg.exe")
set(FFPROBE_EXE "${FFMPEG_CACHE_DIR}/ffprobe.exe")
set(FFMPEG_URL "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip")

if(NOT EXISTS "${FFMPEG_EXE}" OR NOT EXISTS "${FFPROBE_EXE}")
  message(STATUS "[LocalConvert] Descargando binarios estáticos de FFmpeg para Windows...")
  file(MAKE_DIRECTORY "${FFMPEG_CACHE_DIR}")
  set(FFMPEG_ZIP "${FFMPEG_CACHE_DIR}/ffmpeg.zip")
  set(FFMPEG_TMP_EXTRACT "${FFMPEG_CACHE_DIR}/tmp_extract")

  file(DOWNLOAD "${FFMPEG_URL}" "${FFMPEG_ZIP}"
    SHOW_PROGRESS
    STATUS DOWNLOAD_STATUS
    TLS_VERIFY ON
  )

  list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
  list(GET DOWNLOAD_STATUS 1 STATUS_MESSAGE)
  if(NOT STATUS_CODE EQUAL 0)
    file(REMOVE "${FFMPEG_ZIP}")
    message(FATAL_ERROR "[LocalConvert] Error descargando FFmpeg (${STATUS_CODE}): ${STATUS_MESSAGE}")
  endif()

  message(STATUS "[LocalConvert] Extrayendo ffmpeg.exe y ffprobe.exe...")
  file(REMOVE_RECURSE "${FFMPEG_TMP_EXTRACT}")
  file(ARCHIVE_EXTRACT INPUT "${FFMPEG_ZIP}" DESTINATION "${FFMPEG_TMP_EXTRACT}")

  file(GLOB_RECURSE EXTRACTED_FFMPEG "${FFMPEG_TMP_EXTRACT}/ffmpeg.exe")
  file(GLOB_RECURSE EXTRACTED_FFPROBE "${FFMPEG_TMP_EXTRACT}/ffprobe.exe")

  if(NOT EXTRACTED_FFMPEG OR NOT EXTRACTED_FFPROBE)
    message(FATAL_ERROR "[LocalConvert] No se encontraron ffmpeg.exe o ffprobe.exe dentro del archivo descargado.")
  endif()

  list(GET EXTRACTED_FFMPEG 0 FIRST_FFMPEG)
  list(GET EXTRACTED_FFPROBE 0 FIRST_FFPROBE)

  configure_file("${FIRST_FFMPEG}" "${FFMPEG_EXE}" COPYONLY)
  configure_file("${FIRST_FFPROBE}" "${FFPROBE_EXE}" COPYONLY)

  # Limpiar el .zip y archivos de documentación extraídos para ahorrar espacio
  file(REMOVE "${FFMPEG_ZIP}")
  file(REMOVE_RECURSE "${FFMPEG_TMP_EXTRACT}")
  message(STATUS "[LocalConvert] FFmpeg listo en ${FFMPEG_CACHE_DIR}")
endif()

# 1) Copiar tras compilar (necesario para 'flutter run -d windows')
add_custom_target(${BINARY_NAME}_copy_ffmpeg ALL
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${FFMPEG_EXE}" "$<TARGET_FILE_DIR:${BINARY_NAME}>/ffmpeg.exe"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${FFPROBE_EXE}" "$<TARGET_FILE_DIR:${BINARY_NAME}>/ffprobe.exe"
  DEPENDS ${BINARY_NAME}
  COMMENT "Copiando ffmpeg.exe y ffprobe.exe al directorio de salida..."
)

# === Compilación automática del motor nativo Rust (local_convert_core.dll) ===
find_program(CARGO_EXECUTABLE cargo
  HINTS
    "$ENV{USERPROFILE}/.cargo/bin"
    "$ENV{CARGO_HOME}/bin"
  REQUIRED
)
find_program(RUSTC_EXECUTABLE rustc
  HINTS
    "$ENV{USERPROFILE}/.cargo/bin"
    "$ENV{CARGO_HOME}/bin"
  REQUIRED
)

set(RUST_MANIFEST_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../rust/Cargo.toml")
set(RUST_DLL_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../rust/target/release/local_convert_core.dll")

add_custom_target(${BINARY_NAME}_rust_core ALL
  COMMAND ${CMAKE_COMMAND} -E env "RUSTC=${RUSTC_EXECUTABLE}"
    "${CARGO_EXECUTABLE}" build --release --manifest-path "${RUST_MANIFEST_PATH}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${RUST_DLL_PATH}" "$<TARGET_FILE_DIR:${BINARY_NAME}>/local_convert_core.dll"
  DEPENDS ${BINARY_NAME}
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../rust"
  COMMENT "Compilando local_convert_core.dll en Rust y copiando junto al ejecutable..."
)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

# Empaquetar FFmpeg junto al ejecutable Release
install(FILES "${FFMPEG_EXE}" "${FFPROBE_EXE}"
  DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

# Empaquetar librería nativa Rust junto al ejecutable Release
install(FILES "${RUST_DLL_PATH}"
  DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
