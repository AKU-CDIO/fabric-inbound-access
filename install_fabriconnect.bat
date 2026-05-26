@echo off
title Installing fabriconnect...
echo Installing fabriconnect R package from GitHub...
echo.
Rscript -e "remotes::install_github('AKU-CDIO/fabric-inbound-access', subdir = 'fabriconnect', force = TRUE, upgrade_dependencies = FALSE)"
echo.
echo ============================================
echo  Done!
echo ============================================
echo.
echo Open R or RStudio and type:
echo   library(fabriconnect)
echo   conn <- connect_to_fabric()
echo   list_tables(conn)
echo.
pause
