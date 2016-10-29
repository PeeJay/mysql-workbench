@REM This is a generated file.
@echo off
setlocal
SET srcdir="I:\mysql-workbench\deps\pcre"
SET pcretest="I:\mysql-workbench\deps\pcre\build\DEBUG\pcretest.exe"
if not [%CMAKE_CONFIG_TYPE%]==[] SET pcretest="I:\mysql-workbench\deps\pcre\build\%CMAKE_CONFIG_TYPE%\pcretest.exe"
call %srcdir%\RunTest.Bat
if errorlevel 1 exit /b 1
echo RunTest.bat tests successfully completed
