@echo off
title UZIMA Fabric Token Broker — Admin Setup
powershell.exe -ExecutionPolicy Bypass -NoExit -Command "& '%~dp0deploy-token-broker.ps1' -Mode AzureAutomation"
