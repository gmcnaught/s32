@echo off
REM Thin wrapper: build the segas32 profile (Sonic and future non-V25
REM games, HLE only). See tools/build.bat for the actual pipeline.
set S32_PROJECT=segas32
set S32_REVISION=segas32
set S32_RELEASE_NAME=segas32
call "%~dp0build.bat" %*
