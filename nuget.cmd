@ECHO OFF
SET MISSING_PARAMS=0

IF "%NUGET_SOURCE%" == "" (
	ECHO NuGet Source Repository is not set!
	ECHO Generated NuGet packages should be updated to a NuGet Source Repository for easier access via NuGet.
	ECHO You can set it using 'SET NUGET_SOURCE=https://...'.
	SET MISSING_PARAMS=1
)

IF %MISSING_PARAMS% == 0 (
	IF "%NUGET_APIKEY%" == "" (
		ECHO NuGet API Key is not set!
		ECHO The NuGet API Key is required to upload generated NuGet packages to a NuGet repository.
		ECHO You can set it using 'SET NUGET_APIKEY=...'.
		SET MISSING_PARAMS=1
	)
)

IF %MISSING_PARAMS% == 1 (
	GOTO :MISSING_PARAMS
)


:CONFIGURE
SET VTK_SRC=%CD%
PUSHD ..
MKDIR VTK-build
CD VTK-build
SET VTK_NUGET=%CD%\NuGet

SET VERSION=8.1.0

CALL :CONFIGURE_PROJECT "Visual Studio 15 2017" vs15
CALL :BUILD_PROJECT vs15

IF %MISSING_PARAMS% == 0 CALL :PUSH_PROJECT vs15

POPD
GOTO :EOF


:MISSING_PARAMS
SET RESPONSE=
SET /P RESPONSE= "Do you still want to continue (y[es]/[no])? "

IF /I "%RESPONSE%" == "y" GOTO :CONFIGURE
IF /I "%RESPONSE%" == "yes" GOTO :CONFIGURE
GOTO :EOF


:CONFIGURE_PROJECT
ECHO Configuring project for %~1 (%2)...
CALL :CONFIGURE_BUILD "%~1 Win64"	%2-x64-gl2
CALL :CONFIGURE_BUILD "%~1"			%2-x86-gl2
CALL :CONFIGURE_BUILD "%~1 Win64"	%2-x64-gl	OpenGL
CALL :CONFIGURE_BUILD "%~1"			%2-x86-gl	OpenGL
ECHO Configured project for %~1 (%2).
GOTO :EOF


:BUILD_PROJECT
CALL :BUILD %1-x64-gl2
CALL :BUILD %1-x86-gl2
CALL :BUILD %1-x64-gl
CALL :BUILD %1-x86-gl
GOTO :EOF


:PUSH_PROJECT
CALL :PUSH %1-x64-gl2
CALL :PUSH %1-x64-gl
GOTO :EOF


:BUILD
CALL :BUILD_CONFIGURATION %1 debug
CALL :BUILD_CONFIGURATION %1 release
GOTO :EOF


:BUILD_CONFIGURATION
IF EXIST %1.%2.built GOTO :BUILD_EXIST
CD %1
ECHO Building %2 configuration of %1...
MSBuild nuget-pack.vcxproj /target:Build /p:Configuration=%2 /m
ECHO Built %2 configuration of %1.
CD ..
ECHO 1 > %1.%2.built
GOTO :EOF


:BUILD_EXIST
ECHO %1 %2 already built.
GOTO :EOF


:PUSH
CD %1
MSBuild nuget-push.vcxproj /target:Build /p:Configuration=Release /m
CD ..
GOTO :EOF


:CONFIGURE_BUILD
IF EXIST %2.configured (
	GOTO :CONFIGURE_BUILD_EXIST
)

ECHO Configuring %1 %3 build (%2)...
MKDIR "%2"
CD "%2"
cmake ^
	-D BUILD_NUGET:BOOL=TRUE ^
	-D BUILD_TESTING:BOOL=FALSE ^
	-D NUGET_APIKEY=%NUGET_APIKEY% ^
	-D NUGET_PACKAGE_DIR:PATH=%VTK_NUGET% ^
	-D NUGET_SOURCE=%NUGET_SOURCE% ^
	-D NUGET_SUFFIX=%3 ^
	-D VTK_RENDERING_BACKEND:STRING=%3 ^
	-G "%~1" ^
	%VTK_SRC%
CD ..
ECHO Configured %1 %3 build (%2).
ECHO 1 > %2.configured
GOTO :EOF


:CONFIGURE_BUILD_EXIST
ECHO %~1 %3 build (%2) already configured.
GOTO :EOF
