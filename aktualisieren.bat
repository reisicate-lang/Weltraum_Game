@echo off
chcp 65001 >nul
rem Holt den neuesten Stand des Spiels von GitHub.
rem Doppelklick genuegt. Spielstaende werden nicht angefasst.
cd /d "%~dp0"
where git >nul 2>nul
if errorlevel 1 (
  echo Git ist nicht installiert. Bitte von https://git-scm.com/download/win installieren
  echo oder in GitHub Desktop auf "Fetch origin" und dann "Pull origin" klicken.
  pause
  exit /b 1
)
if not exist ".git" (
  echo Dieser Ordner ist keine Git-Kopie (vermutlich als ZIP geladen).
  echo Bitte das Projekt mit GitHub Desktop klonen.
  pause
  exit /b 1
)
rem Godot schreibt project.godot beim Oeffnen um. Diese automatische Aenderung verwerfen,
rem sonst blockiert sie das Holen. Die echte Fassung kommt danach von GitHub.
git checkout -- project.godot
echo Hole den neuesten Stand von GitHub ...
git pull
if errorlevel 1 (
  echo.
  echo Das hat nicht geklappt. Hast du selbst Dateien im Projekt geaendert?
  echo Dann in GitHub Desktop nachsehen.
) else (
  echo.
  echo Fertig. Jetzt Godot oeffnen und mit F5 starten.
)
pause
