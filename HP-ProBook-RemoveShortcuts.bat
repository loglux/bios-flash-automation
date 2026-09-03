@echo off
setlocal enabledelayedexpansion

REM Removes every .lnk shortcut from the target system's Public
REM Desktop. Runs on the LIVE target system (not from WinPE) - after
REM remote configuration is finished, meant to be triggered centrally
REM (e.g. pushed via Altiris/Notification Server, or Invoke-Command/
REM PsExec against a list of hosts) rather than double-clicked one
REM machine at a time.

del "%PUBLIC%\Desktop\*.lnk" /q

echo OK: shortcuts removed from %PUBLIC%\Desktop
exit /b 0
