@echo off
REM ===================================================================
REM  HEIST CREW - let Claude play-test in Roblox Studio
REM  Bridges Studio's built-in MCP server (StudioMCP.exe, stdio) to a
REM  local HTTP port Claude (in Docker) reaches at host.docker.internal:8792.
REM  Close this window = Claude is cut off. Nothing else is changed.
REM ===================================================================
title Studio MCP bridge for Claude (close to disconnect)
node -v >nul 2>&1
if errorlevel 1 (
  echo   [X] Node.js is not installed. Get the LTS version from nodejs.org, then run this again.
  pause
  exit /b 1
)

REM Find the newest StudioMCP.exe that Studio installed (mcp.bat only locates this file)
set "MCPEXE="
for /f "usebackq delims=" %%F in (`powershell -NoProfile -Command "(Get-ChildItem -Path $env:LOCALAPPDATA\Roblox\Versions -Recurse -Filter StudioMCP.exe -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName"`) do set "MCPEXE=%%F"
if not defined MCPEXE (
  echo   [X] Could not find StudioMCP.exe.
  echo       In Studio: Assistant ^> Settings ^> MCP Servers ^> Enable Studio as MCP server, then run this again.
  pause
  exit /b 1
)
echo   Using %MCPEXE%
echo   Bridge running on port 8792. Keep this window open while Claude plays.
echo   Windows may ask about the firewall: allow PRIVATE networks only.
npx -y supergateway --stdio "%MCPEXE%" --outputTransport streamableHttp --stateful --port 8792
pause
