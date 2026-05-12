@echo off
rem Claudario hook bridge for Claude Code on Windows.
rem curl.exe is built into Windows 10 build 1803+ and Windows 11.
rem This script must never block Claude Code — it returns 0 regardless.
curl.exe -s -m 1 -X POST http://127.0.0.1:47821/event ^
  -H "Content-Type: application/json" ^
  --data-binary @- 2>nul
exit /b 0
