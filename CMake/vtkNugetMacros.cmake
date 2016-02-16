set(VTK_NUGET_TEMPLATE ${CMAKE_CURRENT_LIST_DIR}/vtkNuget)

if (MSVC)
  set(NUGET_BUILD OFF CACHE BOOL "Enable NuGet package builds")
else()
  set(NUGET_BUILD OFF)
endif()

if(NUGET_BUILD)
  find_program(NUGET_COMMAND NuGet.exe)
endif()

if(NOT NUGET_BUILD OR NOT NUGET_COMMAND)
  function(vtk_nuget_export type module)
  endfunction()
  return()
endif()

set(NUGET_PACKAGE_DIR ${CMAKE_BINARY_DIR}/NuGet CACHE PATH "Directory used to collect files to be packed in NuGet packages")
set(NUGET_SOURCE "" CACHE STRING "NuGet Gallery Push URL")
set(NUGET_APIKEY "" CACHE STRING "NuGet API Key")
set(NUGET_PACK_VERSION "${VTK_VERSION}-pre-1" CACHE STRING "NuGet Package Version Number")

set(NUGET_ARCH Win32)
if(CMAKE_CL_64)
  set(NUGET_ARCH x64)
endif()

set(NUGET_MSVC_VERSION 14.0)
if(MSVC14)
  set(NUGET_MSVC_VERSION 14.0)
endif()

add_custom_target(nuget-copy)
set_target_properties(nuget-copy PROPERTIES FOLDER NuGet)

add_custom_target(nuget-pack)
set_target_properties(nuget-pack PROPERTIES FOLDER NuGet)

if(NUGET_APIKEY)
  add_custom_target(nuget-push)
  set_target_properties(nuget-push PROPERTIES FOLDER NuGet)
endif()

function(vtk_nuget_export type module)
  string(REGEX REPLACE "([a-z])([A-Z])" "\\1 \\2" vtk_nuget_keywords "${module}")

  set(vtk_nuget_dependencies "${${module}_LINK_DEPENDS};${${module}_PRIVATE_DEPENDS}")
  list(REMOVE_DUPLICATES vtk_nuget_dependencies)

  string(REGEX REPLACE "([^;]+)(;?)" "<dependency id='\\1' version='${NUGET_PACK_VERSION}' />\\2" vtk_nuget_dependencies "${vtk_nuget_dependencies}")
  string(REPLACE ";" "\n      " vtk_nuget_dependencies "${vtk_nuget_dependencies}")

  set(nuget_obj ${NUGET_PACKAGE_DIR}/obj/${module})
  set(nuget_native ${nuget_obj}/build/native)
  set(nuget_lib ${nuget_native}/lib/${NUGET_MSVC_VERSION}/${NUGET_ARCH}/$<CONFIG>)
  set(nuget_bin ${NUGET_PACKAGE_DIR}/bin)
  #file(MAKE_DIRECTORY ${nuget_native}/lib)
  #file(MAKE_DIRECTORY ${nuget_native}/include)
  #file(MAKE_DIRECTORY ${nuget_native}/include/${NUGET_MSVC_VERSION}/${NUGET_ARCH})

  file(GLOB generated_headers ${CMAKE_CURRENT_BINARY_DIR}/*.h*)
  set(all_headers ${generated_headers};${_hdrs};${ARGN})
  if(all_headers)
    list(REMOVE_DUPLICATES all_headers)
  endif()

  set(copy_sources)
  foreach(header ${all_headers})
    if(header MATCHES "=>")
      string(REGEX REPLACE "(.*)=>.*" "\\1" header_source "${header}")
      string(REGEX REPLACE ".*=>(.*)" "\\1" header_target "${header}")
      # file(COPY ${header_source} DESTINATION ${nuget_native}/include/${header_target}/)
      get_filename_component(header_name ${header_source} NAME)
      set(header_path ${nuget_native}/include/${header_target})
    else()
      set(header_source ${header})
      if(header MATCHES "^${CMAKE_CURRENT_BINARY_DIR}")
        #file(COPY ${header} DESTINATION ${nuget_native}/include/${NUGET_MSVC_VERSION}/${NUGET_ARCH})
        file(RELATIVE_PATH header_target ${CMAKE_CURRENT_BINARY_DIR} ${header})
        set(header_target ${nuget_native}/include/${NUGET_MSVC_VERSION}/${NUGET_ARCH}/${header_target})
      else()
        #file(COPY ${header} DESTINATION ${nuget_native}/include)
        set(header_target ${nuget_native}/include/${header_target})
      endif()
      get_filename_component(header_path ${header_target} DIRECTORY)
      get_filename_component(header_name ${header_target} NAME)
    endif()

    add_custom_command(OUTPUT ${header_path}/${header_name} COMMAND
      ${CMAKE_COMMAND} -E make_directory ${header_path} &&
      ${CMAKE_COMMAND} -E copy_if_different ${header_source} ${header_path}/${header_name})
    list(APPEND copy_sources ${header_path}/${header_name})
  endforeach()

  configure_file(${VTK_NUGET_TEMPLATE}.nuspec.in ${module}.nuspec.in)
  #file(GENERATE OUTPUT ${nuget_obj}/${module}.nuspec INPUT ${CMAKE_CURRENT_BINARY_DIR}/${module}.nuspec.in)
  file(GENERATE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}}/${module}.nuspec INPUT ${CMAKE_CURRENT_BINARY_DIR}/${module}.nuspec.in)
  add_custom_command(OUTPUT ${nuget_obj}/${module}.nuspec COMMAND
    ${CMAKE_COMMAND} -E make_directory ${nuget_obj} &&
    ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}}/${module}.nuspec ${nuget_obj}/${module}.nuspec)
  list(APPEND copy_sources ${nuget_obj}/${module}.nuspec)

  configure_file(${VTK_NUGET_TEMPLATE}.common.targets.in ${module}.common.targets.in)
  #file(GENERATE OUTPUT ${nuget_native}/${module}.targets INPUT ${CMAKE_CURRENT_BINARY_DIR}/${module}.common.targets.in)
  file(GENERATE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}}/${module}.targets INPUT ${CMAKE_CURRENT_BINARY_DIR}/${module}.common.targets.in)
  add_custom_command(OUTPUT ${nuget_native}/${module}.targets COMMAND
    ${CMAKE_COMMAND} -E make_directory ${nuget_native} &&
    ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}}/${module}.targets ${nuget_native}/${module}.targets)
  list(APPEND copy_sources ${nuget_native}/${module}.targets)

  add_custom_target(nuget-copy-${module} SOURCES ${copy_sources})
  set_target_properties(nuget-copy-${module} PROPERTIES FOLDER "NuGet/copy")
  add_dependencies(nuget-copy nuget-copy-${module})

  if(type STREQUAL LIBRARY)
    configure_file(${VTK_NUGET_TEMPLATE}.targets.in ${module}.targets.in)
    #file(GENERATE OUTPUT ${nuget_lib}/Custom${module}.targets INPUT ${CMAKE_CURRENT_BINARY_DIR}/${module}.targets.in)
    file(GENERATE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}}/Custom${module}.targets INPUT ${CMAKE_CURRENT_BINARY_DIR}/${module}.targets.in)
    add_custom_command(TARGET nuget-copy-${module} COMMAND
      ${CMAKE_COMMAND} -E make_directory ${nuget_lib} &&
      ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}}/Custom${module}.targets ${nuget_lib}/Custom${module}.targets)

    add_custom_command(TARGET nuget-copy-${module} POST_BUILD COMMAND
      ${CMAKE_COMMAND} -E make_directory ${nuget_lib} &&
      IF EXIST $<TARGET_FILE:${module}> ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${module}> ${nuget_lib} &&
      IF EXIST $<TARGET_LINKER_FILE:${module}> ${CMAKE_COMMAND} -E copy_if_different $<TARGET_LINKER_FILE:${module}> ${nuget_lib})

    get_target_property(module_type ${module} TYPE)
    if(${module_type} STREQUAL SHARED_LIBRARY OR ${module_type} STREQUAL MODULE_LIBRARY)
      add_custom_command(TARGET nuget-copy-${module} POST_BUILD COMMAND
        IF EXIST $<TARGET_PDB_FILE:${module}> ${CMAKE_COMMAND} -E copy_if_different $<TARGET_PDB_FILE:${module}> ${nuget_lib})
    endif()
  endif()
  
  set(nuget_package ${nuget_bin}/${module}.${NUGET_PACK_VERSION}.nupkg)
  add_custom_command(OUTPUT ${nuget_package} COMMAND
    ${CMAKE_COMMAND} -E make_directory ${nuget_bin} &&
    ${NUGET_COMMAND} pack -OutputDirectory ${nuget_bin}
    DEPENDS nuget-copy-${module} ${nuget_obj}/${module}.nuspec
    WORKING_DIRECTORY ${nuget_obj})

  add_custom_target(nuget-pack-${module} SOURCES ${nuget_package})
  set_target_properties(nuget-pack-${module} PROPERTIES FOLDER "NuGet/pack")
  add_dependencies(nuget-pack nuget-pack-${module})

  if(NUGET_APIKEY)
    set(nuget_options -ApiKey ${NUGET_APIKEY})
    if(NUGET_SOURCE)
      set(nuget_options ${nuget_options} -Source ${NUGET_SOURCE})
    endif()
    add_custom_command(OUTPUT ${nuget_package}.pushed COMMAND
      ${NUGET_COMMAND} push ${nuget_package} ${nuget_options} &&
      ${CMAKE_COMMAND} -E touch ${nuget_package}.pushed DEPENDS ${nuget_package})
    add_custom_target(nuget-push-${module} SOURCES ${nuget_package}.pushed)
    set_target_properties(nuget-push-${module} PROPERTIES FOLDER "NuGet/push")
    add_dependencies(nuget-push nuget-push-${module})
  endif()
endfunction()
