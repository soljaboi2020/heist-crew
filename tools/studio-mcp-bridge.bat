@echo off
REM ===================================================================
REM  HEIST CREW - let Claude play-test in Roblox Studio
REM  Bridges Studio's built-in MCP server (stdio, localhost only) to a
REM  local HTTP port that Claude (running in Docker) can reach at
REM  host.docker.internal:8792. Close this window = Claude is cut off.
REM ===================================================================
title Studio MCP bridge for Claude (close to disconnect)
node -v >nul 2>&1
if errorlevel 1 (
  echo   [X] Node.js is not installed. Get the LTS version from nodejs.org, then run this again.
  pause
  exit /b 1
)
if not exist "%LOCALAPPDATA%\Roblox\mcp.bat" (
  echo   [X] Studio's MCP server isn't turned on yet.
  echo       In Studio: Assistant ^> Settings ^> MCP Servers ^> Enable Studio as MCP server
  pause
  exit /b 1
)
echo   Bridge running on port 8792. Keep this window open while Claude plays.
echo   Windows may ask about the firewall: allow PRIVATE networks only.
npx -y supergateway --stdio "cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat" --outputTransport streamableHttp --port 8792
pause
