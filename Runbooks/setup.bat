@echo off
title UZIMA Fabric Token Broker -- Admin Setup
echo ============================================
echo   UZIMA Fabric Token Broker Setup
echo ============================================
echo.
echo This will authenticate you (admin) via device code,
echo store tokens locally, and set up auto-refresh.
echo.
echo You need access to the Fabric tenant to authenticate.
echo.
pause
powershell.exe -ExecutionPolicy Bypass -NoExit -Command "& '%~dp0deploy-token-broker.ps1' -Mode LocalVM"
