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
  function(vtk_nuget_export)
  endfunction()
  return()
endif()

set(NUGET_PACKAGE_DIR ${CMAKE_BINARY_DIR}/NuGet CACHE PATH "Directory used to collect files to be packed in NuGet packages")
set(NUGET_SOURCE "" CACHE STRING "NuGet Gallery Push URL")
set(NUGET_APIKEY "" CACHE STRING "NuGet API Key")
set(NUGET_PACK_VERSION "${VTK_VERSION}-prerelease-1" CACHE STRING "NuGet Package Version Number")

set(NUGET_ARCH Win32)
if(CMAKE_CL_64)
  set(NUGET_ARCH x64)
endif()

set(NUGET_MSVC_VERSION 14.0)
if(MSVC14)
  set(NUGET_MSVC_VERSION 14.0)
endif()

add_custom_target(nuget-pack)
set_target_properties(nuget-pack PROPERTIES FOLDER NuGet)

if(NUGET_APIKEY)
  add_custom_target(nuget-push)
  set_target_properties(nuget-push PROPERTIES FOLDER NuGet)
endif()

function(vtk_nuget_export)
  string(REGEX REPLACE "([a-z])([A-Z])" "\\1 \\2" vtk_nuget_keywords "${vtk-module}")

  set(vtk_nuget_dependencies "${${vtk-module}_LINK_DEPENDS};${${vtk-module}_PRIVATE_DEPENDS}")
  list(REMOVE_DUPLICATES vtk_nuget_dependencies)
  string(REGEX REPLACE "([^;]+)(;?)" "<dependency id='\\1' version='${NUGET_PACK_VERSION}' />\\2" vtk_nuget_dependencies "${vtk_nuget_dependencies}")
  string(REPLACE ";" "\n      " vtk_nuget_dependencies "${vtk_nuget_dependencies}")

  set(nuget_obj ${NUGET_PACKAGE_DIR}/obj/${vtk-module})
  set(nuget_native ${nuget_obj}/build/native)
  set(nuget_lib ${nuget_native}/lib/${NUGET_MSVC_VERSION}/${NUGET_ARCH}/$<CONFIG>)
  set(nuget_bin ${NUGET_PACKAGE_DIR}/bin)
  file(MAKE_DIRECTORY ${nuget_native}/lib)
  file(MAKE_DIRECTORY ${nuget_native}/include)
  file(MAKE_DIRECTORY ${nuget_native}/include/${NUGET_MSVC_VERSION}/${NUGET_ARCH})

  foreach(header ${_hdrs})
    if(header MATCHES "^${CMAKE_CURRENT_BINARY_DIR}")
      file(COPY ${header} DESTINATION ${nuget_native}/include/${NUGET_MSVC_VERSION}/${NUGET_ARCH})
    else()
      file(COPY ${header} DESTINATION ${nuget_native}/include)
    endif()
  endforeach()

  configure_file(${VTK_NUGET_TEMPLATE}.nuspec.in ${vtk-module}.nuspec.in)
  configure_file(${VTK_NUGET_TEMPLATE}.common.targets.in ${vtk-module}.common.targets.in)
  configure_file(${VTK_NUGET_TEMPLATE}.targets.in ${vtk-module}.targets.in)
  file(GENERATE OUTPUT ${nuget_obj}/${vtk-module}.nuspec INPUT ${CMAKE_CURRENT_BINARY_DIR}/${vtk-module}.nuspec.in)
  file(GENERATE OUTPUT ${nuget_native}/${vtk-module}.targets INPUT ${CMAKE_CURRENT_BINARY_DIR}/${vtk-module}.common.targets.in)
  file(GENERATE OUTPUT ${nuget_lib}/${vtk-module}.targets INPUT ${CMAKE_CURRENT_BINARY_DIR}/${vtk-module}.targets.in)

  add_custom_command(TARGET ${vtk-module} POST_BUILD COMMAND
    ${CMAKE_COMMAND} -E make_directory ${nuget_lib} &&
    IF EXIST $<TARGET_FILE:${vtk-module}> ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${vtk-module}> ${nuget_lib} &&
    IF EXIST $<TARGET_LINKER_FILE:${vtk-module}> ${CMAKE_COMMAND} -E copy_if_different $<TARGET_LINKER_FILE:${vtk-module}> ${nuget_lib} &&
    IF EXIST $<TARGET_PDB_FILE:${vtk-module}> ${CMAKE_COMMAND} -E copy_if_different $<TARGET_PDB_FILE:${vtk-module}> ${nuget_lib})

  set(nuget_package ${nuget_bin}/${vtk-module}.${NUGET_PACK_VERSION}.nupkg)
  add_custom_command(OUTPUT ${nuget_package} COMMAND
    ${CMAKE_COMMAND} -E make_directory ${nuget_bin} &&
    ${NUGET_COMMAND} pack -OutputDirectory ${nuget_bin}
    DEPENDS ${vtk-module}
    WORKING_DIRECTORY ${nuget_obj})
  add_custom_target(nuget-pack-${vtk-module} SOURCES ${nuget_package})
  set_target_properties(nuget-pack-${vtk-module} PROPERTIES FOLDER "NuGet/pack")
  add_dependencies(nuget-pack nuget-pack-${vtk-module})

  if(NUGET_APIKEY)
    set(nuget_options -ApiKey ${NUGET_APIKEY})
    if(NUGET_SOURCE)
      set(nuget_options ${nuget_options} -Source ${NUGET_SOURCE})
    endif()
    add_custom_command(OUTPUT ${nuget_package}.pushed COMMAND
      ${NUGET_COMMAND} push ${nuget_package} ${nuget_options} &&
      ${CMAKE_COMMAND} -E touch ${nuget_package}.pushed DEPENDS ${nuget_package})
    add_custom_target(nuget-push-${vtk-module} SOURCES ${nuget_package}.pushed)
    set_target_properties(nuget-push-${vtk-module} PROPERTIES FOLDER "NuGet/push")
    add_dependencies(nuget-push nuget-push-${vtk-module})
  endif()
endfunction()
