#
# NuGet Package Generation for VTK
#
# To enable NuGet package generation you need to
#  - choose one of the Visual Studio generators,
#  - set BUILD_NUGET to ON,
#  - specify a path to NuGet.exe in NUGET_COMMAND,
#  - specify a package directory to generate and store packages in using NUGET_PACKAGE_DIR;
#      You can either let CMake configure a default subdirectory in the build directory or
#      specify your own directory if you plan to generate packages for multiple platforms or
#      Visual Studio versions;
#  - specify package version in NUGET_PACK_VERSION.
#      CMake will use VTK_VERSION (e.g. 7.1.0) by default, however you could add a suffix here
#      (e.g. 7.1.0-pre-1) to generate pre-release packages first, before producing actual release
#      packages.
#
# To also enable upload / push the generated packages to a NuGet gallery during build you need to
#  - specify your NuGet API key for the upload;
#  - optionally set NUGET_SOURCE to the URL of your NuGet gallery.
#      Packages will be uploaded to the official NuGet gallery if this setting is left empty.
#
# The generation of NuGet packages can be then executed either using the 'NuGet/nuget-pack' target or
#   using one of the module-specific 'NuGet/pack/nuget-pack-<module>' targets.
#
# The upload (and - if required - the generation) of NuGet packages can be similarly executed either using
#   the 'NuGet/nuget-push' target or one of the module-specific 'NuGet/push/nuget-push-<module>' targets.
#
# Verify the NUGET_ CMake configuration settings if none of those targets is available.
#
# The upload step is separated in its own target to support the generation of packages for multiple build
#   configurations, platforms or Visual Studio versions. Each additional platform build or build configuration
#   will regenerate the same packages and add new platform- or configuration-specific binaries and
#   includes. The upload targets should then only be executed after all desired configurations and platforms
#   were already built.
#
# modiCAS GmbH  2016-2018  Alexander Saratow
#
set(VTK_NUGET_TEMPLATE ${CMAKE_CURRENT_LIST_DIR}/vtkNuget)

# allow NuGet packaging only for MSVC builds
if (MSVC)
  set(BUILD_NUGET OFF CACHE BOOL "Enable NuGet package builds")
else()
  set(BUILD_NUGET OFF)
endif()

# search for NuGet.exe if NuGet packaging was requested
if(BUILD_NUGET)
  find_program(NUGET_COMMAND NuGet.exe)
endif()

# declare an empty function stub and leave if either NuGet packaging is not enabled
# or if the NuGet.exe tool was not found, as it is required to build and upload the packages
if(NOT BUILD_NUGET OR NOT NUGET_COMMAND)
  function(vtk_nuget_export type module)
  endfunction()
  return()
endif()

set(NUGET_SUGGESTED_SUFFIX ${VTK_RENDERING_BACKEND})
if(NOT BUILD_SHARED_LIBS)
  set(NUGET_SUGGESTED_SUFFIX static-${VTK_RENDERING_BACKEND})
endif()

set(NUGET_PACKAGE_DIR ${CMAKE_BINARY_DIR}/NuGet CACHE PATH "Directory used to collect files to be packed in NuGet packages")
set(NUGET_SOURCE "" CACHE STRING "NuGet Gallery Push URL")
set(NUGET_APIKEY "" CACHE STRING "NuGet API Key")
set(NUGET_PACK_VERSION "${VTK_VERSION}" CACHE STRING "NuGet Package Version Number")
set(NUGET_SUFFIX "${NUGET_SUGGESTED_SUFFIX}" CACHE STRING "NuGet Package Suffix (e.g. static-OpenGL2")

# determine MSBuild-compatible architecture string
set(NUGET_ARCH Win32)
if(CMAKE_CL_64)
  set(NUGET_ARCH x64)
endif()

# determine MSBuild-compatible visual studio version string
set(NUGET_MSVC_VERSION 15.0)
if(MSVC10)
  set(NUGET_MSVC_VERSION 10.0)
elseif(MSVC11)
  set(NUGET_MSVC_VERSION 11.0)
elseif(MSVC12)
  set(NUGET_MSVC_VERSION 12.0)
elseif(MSVC14)
  set(NUGET_MSVC_VERSION 14.0)
elseif(MSVC15)
  set(NUGET_MSVC_VERSION 15.0)
else()
  message(WARNING "Could not determine MSVC version. Using ${NUGET_MSVC_VERSION} as fallback.")
endif()

# define a target to generate all NuGet packages
add_custom_target(nuget-pack)
set_target_properties(nuget-pack PROPERTIES FOLDER NuGet)

# also define a separate target to upload all NuGet packages
if(NUGET_APIKEY)
  add_custom_target(nuget-push)
  set_target_properties(nuget-push PROPERTIES FOLDER NuGet)
endif()

###
# Export build targets to generate and upload NuGet packages.
# type   - The type of packaged module: either LIBRARY for actually built libraries or
#            INCLUDES for an include-only package (see Utilities/KWIML module)
# module - Name of the module to be packaged
# ...    - Optional list of additional includes. You can supply some or all of the
#            additional headers using the format 'source=>target' (e.g. some_header.h=>directory)
#            to override the name of the target directory where the header file should be packaged.
#            See Utilities/KWIML module for an example.
#
function(vtk_nuget_export type module)
  cmake_parse_arguments(NUGET "" "NAME" "HEADERS" ${ARGN})
  if(NOT NUGET_NAME)
    set(NUGET_NAME ${module})
  endif()
  if(NUGET_SUFFIX)
    set(NUGET_NAME ${NUGET_NAME}-${NUGET_SUFFIX})
  endif()

  # build some package keywords from module name
  string(REGEX REPLACE "([a-z])([A-Z])" "\\1 \\2" vtk_nuget_keywords "${module}")

  # determine module dependencies
  set(vtk_nuget_dependency_list "${${module}_LINK_DEPENDS};${${module}_PRIVATE_DEPENDS}")
  list(REMOVE_DUPLICATES vtk_nuget_dependency_list)
  set(dependency_suffix)
  if(NUGET_SUFFIX)
    set(dependency_suffix "-${NUGET_SUFFIX}")
  endif()
  foreach(dependency ${vtk_nuget_dependency_list})
    set(vtk_nuget_dependencies "${vtk_nuget_dependencies}\n      <dependency id='${dependency}${dependency_suffix}' version='${NUGET_PACK_VERSION}' />")
  endforeach()

  # define some target folders
  set(nuget_obj ${NUGET_PACKAGE_DIR}/obj/${NUGET_NAME})
  set(nuget_native ${nuget_obj}/build/native)
  set(nuget_lib ${nuget_native}/lib/${NUGET_MSVC_VERSION}/${NUGET_ARCH}/$<CONFIG>)
  set(nuget_bin ${NUGET_PACKAGE_DIR}/bin)

  # scan for any generated headers in current build directory that have eventually not been added
  # to the list of module headers
  file(GLOB generated_headers ${CMAKE_CURRENT_BINARY_DIR}/*.h*)
  # also add an expected module header file, which is defined at a later time in vtk_module_library
  set(all_headers ${generated_headers};${_hdrs};${NUGET_HEADERS};${CMAKE_CURRENT_BINARY_DIR}/${module}Module.h)

  # clean up header list, but only if there are any headers at all
  # (there are some modules where this seems not to be the case)
  if(all_headers)
    set(temp_headers)
    # resolve any source-relative headers to their full paths to properly detect duplicates later
    foreach(header ${all_headers})
      if(IS_ABSOLUTE ${header})
        list(APPEND temp_headers ${header})
      else()
        list(APPEND temp_headers ${CMAKE_CURRENT_SOURCE_DIR}/${header})
      endif()
    endforeach()
    set(all_headers ${temp_headers})
    list(REMOVE_DUPLICATES all_headers)
  endif()

  # do not copy headers during configuration but generate custom build steps instead
  set(copy_headers)
  foreach(header ${all_headers})
    # check for the special header rename format first
    if(header MATCHES "=>")
      string(REGEX REPLACE "(.*)=>.*" "\\1" header_source "${header}")
      string(REGEX REPLACE ".*=>(.*)" "\\1" header_target "${header}")
      set(header_path ${nuget_native}/include/${header_target})
      set(header ${header_source})
    else()
      if(header MATCHES "^${CMAKE_CURRENT_BINARY_DIR}")
        # copy headers from build directory to a platform- and configuration-specific location
        file(RELATIVE_PATH header_path ${CMAKE_CURRENT_BINARY_DIR} ${header})
        get_filename_component(header_subpath ${header_path} DIRECTORY)
        set(header_path ${nuget_native}/include/${NUGET_MSVC_VERSION}/${NUGET_ARCH})
        if(header_subpath)
          set(header_path ${header_path}/${header_subpath})
        endif()
      elseif(header MATCHES "^${CMAKE_CURRENT_SOURCE_DIR}")
        # strip source directory path from target header path
        file(RELATIVE_PATH header_path ${CMAKE_CURRENT_SOURCE_DIR} ${header})
        get_filename_component(header_subpath ${header_path} DIRECTORY)
        set(header_path ${nuget_native}/include)
        if(header_subpath)
          set(header_path ${header_path}/${header_subpath})
        endif()
      else()
        # warn about any external headers (there should be none)
        message(WARN "External header: ${header}")
        set(header_path ${nuget_native}/include)
      endif()
    endif()

    # finally generate the build step
    get_filename_component(header_name ${header} NAME)
    add_custom_command(OUTPUT ${header_path}/${header_name}
      COMMAND ${CMAKE_COMMAND} -E make_directory ${header_path}
      COMMAND IF EXIST ${header} ${CMAKE_COMMAND} -E copy_if_different ${header} ${header_path}
      DEPENDS ${header})
    list(APPEND copy_headers ${header_path}/${header_name})
    list(APPEND vtk_nuget_keywords ${header_name})
  endforeach()

  # configure and generate the NuGet package spec
  string(REPLACE ";" " " vtk_nuget_keywords "${vtk_nuget_keywords}")
  configure_file(${VTK_NUGET_TEMPLATE}.nuspec.in ${NUGET_NAME}.nuspec.in)
  file(GENERATE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${NUGET_NAME}.nuspec INPUT ${CMAKE_CURRENT_BINARY_DIR}/${NUGET_NAME}.nuspec.in)
  add_custom_command(OUTPUT ${nuget_obj}/${NUGET_NAME}.nuspec
    COMMAND ${CMAKE_COMMAND} -E make_directory ${nuget_obj}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}/${NUGET_NAME}.nuspec ${nuget_obj}
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${NUGET_NAME}.nuspec)
  list(APPEND copy_headers ${nuget_obj}/${NUGET_NAME}.nuspec)

  set(module_implements ${${module}_IMPLEMENTS})

  # configure and generate custom targets file to be inserted into a project referencing the package
  configure_file(${VTK_NUGET_TEMPLATE}.common.targets.in ${NUGET_NAME}.common.targets.in)
  file(GENERATE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${NUGET_NAME}.targets INPUT ${CMAKE_CURRENT_BINARY_DIR}/${NUGET_NAME}.common.targets.in)
  add_custom_command(OUTPUT ${nuget_native}/${NUGET_NAME}.targets
    COMMAND ${CMAKE_COMMAND} -E make_directory ${nuget_native}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}/${NUGET_NAME}.targets ${nuget_native}
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${NUGET_NAME}.targets)
  list(APPEND copy_headers ${nuget_native}/${NUGET_NAME}.targets)

  # generate the pack step and define the module packaging target
  set(nuget_package ${nuget_bin}/${NUGET_NAME}.${NUGET_PACK_VERSION}.nupkg)
  add_custom_command(OUTPUT ${nuget_package} COMMAND
    ${CMAKE_COMMAND} -E make_directory ${nuget_bin} &&
    ${NUGET_COMMAND} pack -OutputDirectory ${nuget_bin}
    DEPENDS ${module} ${nuget_obj}/${NUGET_NAME}.nuspec ${copy_headers}
    WORKING_DIRECTORY ${nuget_obj})

  add_custom_target(nuget-pack-${module} SOURCES ${nuget_package})
  set_target_properties(nuget-pack-${module} PROPERTIES FOLDER "NuGet/pack")
  add_dependencies(nuget-pack nuget-pack-${module})

  # if the module is a library (which is usually the case)
  if(type STREQUAL LIBRARY)
    # configure and generate a platform-specific targets file with platform-specific build properties
    configure_file(${VTK_NUGET_TEMPLATE}.targets.in ${NUGET_NAME}.targets.in)
    file(GENERATE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Custom_${NUGET_NAME}_$<CONFIG>.targets INPUT ${CMAKE_CURRENT_BINARY_DIR}/${NUGET_NAME}.targets.in)
    add_custom_command(TARGET nuget-pack-${module} PRE_BUILD
      COMMAND ${CMAKE_COMMAND} -E make_directory ${nuget_lib}
      COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}/Custom_${NUGET_NAME}_$<CONFIG>.targets ${nuget_lib}/Custom_${NUGET_NAME}.targets)

    # add a command to copy library binary and according symbols file to packaging directory
    add_custom_command(TARGET nuget-pack-${module} PRE_BUILD
      COMMAND ${CMAKE_COMMAND} -E make_directory ${nuget_lib}
      COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${module}> ${nuget_lib})

    # also add a command to copy the linker file for shared or module libraries
    get_target_property(module_type ${module} TYPE)
    if(${module_type} STREQUAL SHARED_LIBRARY OR ${module_type} STREQUAL MODULE_LIBRARY)
      add_custom_command(TARGET nuget-pack-${module} PRE_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_LINKER_FILE:${module}> ${nuget_lib}
        COMMAND IF EXIST $<TARGET_PDB_FILE:${module}> ${CMAKE_COMMAND} -E copy_if_different $<TARGET_PDB_FILE:${module}> ${nuget_lib})
    endif()
  endif()

  # add push target if there is an API key for the uploads
  if(NUGET_APIKEY)
    set(nuget_options -ApiKey ${NUGET_APIKEY})
    if(NUGET_SOURCE)
      set(nuget_options ${nuget_options} -Source ${NUGET_SOURCE})
    endif()
    add_custom_command(OUTPUT ${nuget_package}.pushed
      COMMAND ${NUGET_COMMAND} push ${nuget_package} ${nuget_options}
      COMMAND ${CMAKE_COMMAND} -E touch ${nuget_package}.pushed
      DEPENDS ${nuget_package})
    add_custom_target(nuget-push-${module} SOURCES ${nuget_package}.pushed)
    set_target_properties(nuget-push-${module} PROPERTIES FOLDER "NuGet/push")
    add_dependencies(nuget-push nuget-push-${module})
    add_dependencies(nuget-push-${module} nuget-pack-${module})
  endif()
endfunction()
