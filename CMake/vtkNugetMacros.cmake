set(VTK_NUGET_TEMPLATE ${CMAKE_CURRENT_LIST_DIR}/vtkNuget)

set(NUGET_BUILD NO CACHE BOOL "Enable NuGet package builds")

if(NUGET_BUILD)
  find_program(NUGET_COMMAND NuGet.exe)
endif()

if(NOT NUGET_BUILD OR NUGET_COMMAND STREQUAL NUGET_COMMMAND-NOTFOUND)
  function(vtk_nuget_export)
  endfunction()
  return()
endif()

set(NUGET_PACKAGE_DIR ${CMAKE_BINARY_DIR}/NuGet CACHE PATH "Directory used to collect files to be packed in NuGet packages")

function(vtk_nuget_export)
  # message("Module: ${vtk-module} ${VTK_VERSION}")
  message("Headers: ${_hdrs}")
  message("Dependencies: ${${vtk-module}_LINK_DEPENDS} Private: ${${vtk-module}_PRIVATE_DEPENDS}")

  string(REGEX REPLACE "([a-z])([A-Z])" "\\1 \\2" vtk-nuget-keywords "${vtk-module}")
  string(REGEX REPLACE "([^;]+)(;?)" "<dependency id='\\1' version='${VTK_VERSION}' />\\2" vtk-nuget-dependencies "${${vtk-module}_LINK_DEPENDS};${${vtk-module}_PRIVATE_DEPENDS}")
  string(REPLACE ";" "\n      " vtk-nuget-dependencies "${vtk-nuget-dependencies}")
  string(REPLACE "/" "\\" vtk-nuget-files "${_hdrs}")
  string(REGEX REPLACE "([^;]+)(;?)" "<file src='\\1' target='build\\\\native\\\\include' />\\2" vtk-nuget-files "${vtk-nuget-files}")
  string(REPLACE ";" "\n    " vtk-nuget-files "${vtk-nuget-files}")

  configure_file(${VTK_NUGET_TEMPLATE}.nuspec.in ${vtk-module}.nuspec.in)
  configure_file(${VTK_NUGET_TEMPLATE}.targets.in ${vtk-module}.targets.in)
  file(GENERATE OUTPUT $<TARGET_FILE_DIR:${vtk-module}>/${vtk-module}.nuspec INPUT ${CMAKE_CURRENT_BINARY_DIR}/${vtk-module}.nuspec.in)
  file(GENERATE OUTPUT $<TARGET_FILE_DIR:${vtk-module}>/${vtk-module}.targets INPUT ${CMAKE_CURRENT_BINARY_DIR}/${vtk-module}.targets.in)
  # add_custom_command(OUTPUT ${vtk-module}.nuspec ${CMAKE_COMMAND}   )
endfunction()
