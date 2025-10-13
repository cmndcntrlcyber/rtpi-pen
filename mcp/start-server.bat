@echo off
echo Starting RTPI-Pen MCP Server...

REM Check if Python is available
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python is not installed or not in PATH
    echo Please install Python from https://python.org/
    pause
    exit /b 1
)

REM Change to MCP directory
cd /d "%~dp0"

REM Install dependencies if needed
echo Installing/updating Python dependencies...
pip install -r requirements.txt
if %errorlevel% neq 0 (
    echo Failed to install dependencies
    echo Trying with --user flag...
    pip install --user -r requirements.txt
    if %errorlevel% neq 0 (
        echo Failed to install dependencies with --user flag
        pause
        exit /b 1
    )
)

REM Make server executable
chmod +x src/server.py 2>nul

REM Start the MCP server
echo Starting RTPI-Pen MCP server...
python src/server.py

pause
