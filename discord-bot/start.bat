@echo off
chcp 65001 >nul
title Weak Spot Contest Bot
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 goto nonode

if not exist ".env" goto noenv

if exist "node_modules" goto deploy
echo Installiere den Bot, das dauert beim ersten Mal ein paar Sekunden ...
call npm install
if errorlevel 1 goto failed

:deploy
echo Registriere die Befehle bei Discord ...
call npm run deploy
if errorlevel 1 goto failed

echo.
echo Bot startet ... Dieses Fenster offen lassen! Fenster schliessen = Bot aus.
echo.
call npm start
goto end

:nonode
echo Node.js fehlt!
echo Lade es hier herunter und installiere es: https://nodejs.org  - die LTS-Version nehmen
echo Danach diese Datei nochmal doppelklicken.
goto end

:noenv
copy ".env.example" ".env" >nul
echo Die Datei .env wurde erstellt und oeffnet sich jetzt im Editor.
echo Trage dort DISCORD_TOKEN, CLIENT_ID und GUILD_ID ein, speichere mit Strg+S
echo und doppelklicke danach start.bat nochmal.
notepad ".env"
goto end

:failed
echo.
echo Da ist etwas schiefgelaufen - lies die Fehlermeldung oben.
echo Meistens ist ein Wert in der .env falsch, zum Beispiel der Token.

:end
echo.
pause
