@echo off
REM Thin wrapper: build the segas32v25 profile (ga2, arabfgt: real V25).
REM See tools/build.bat for the actual pipeline.
set S32_PROJECT=segas32v25
set S32_REVISION=segas32v25
set S32_RELEASE_NAME=segas32v25
call "%~dp0build.bat" %*
