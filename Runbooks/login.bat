@echo off
title UZIMA Fabric Data Access
echo ============================================
echo     UZIMA Fabric Data Access
echo ============================================
echo.
echo  1. Local token (fast, no sign-in needed)
echo  2. Webhook token (requires Azure CLI sign-in)
echo  3. Python interactive
echo.
set /p choice="Enter choice (1-3): "

if "%choice%"=="1" goto local
if "%choice%"=="2" goto webhook
if "%choice%"=="3" goto python
goto end

:local
powershell.exe -ExecutionPolicy Bypass -File "%~dp0vm-token-client-local.ps1"
goto end

:webhook
echo.
echo Make sure you're signed into Azure CLI first:
echo   az login --scope https://management.azure.com/.default --use-device-code
echo.
pause
powershell.exe -ExecutionPolicy Bypass -File "%~dp0vm-token-client.ps1"
goto end

:python
python -c "from fabricpy import FabricLakehouse; lh = FabricLakehouse(); print('Tables:', len(lh.list_tables()))"
pause
goto end

:end
