@echo off
setlocal

set exitFail=EXIT /b 1
set exitOk=EXIT /b 0

SET cmdName=%~n0
SET cmdNameExt=%~n0%~x0
SET cmdPath=%~p0
SET cmdTitle=%cmdNameExt%: Restore databse from the snapshot. by mazzy, v2016-10-12
TITLE %cmdTitle%

ECHO.
ECHO %cmdTitle%
ECHO Use parameter -h for more help. see also https://github.com/mazzy-ax/ax7db-reset

set services=DynamicsAxBatch MR2012ProcessService Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe MSSQLServerOLAPService ReportServer

:ParmLoop
CALL :isParmStr "%1" "%2" "db"              "AxDbRain"                 && shift && shift && goto :ParmLoop
CALL :isParmStr "%1" "%2" "snapshot"        "AxDBRAINInitialDataState" && shift && shift && goto :ParmLoop
CALL :isParmStr "%1" "%2" "servicesToStop"  "%services%"               && shift && shift && goto :ParmLoop
CALL :isParmStr "%1" "%2" "servicesToStart" "%services%"               && shift && shift && goto :ParmLoop
CALL :isParmStr "%1" "%2" "log"             "nul"                      && shift && shift && goto :ParmLoop
CALL :isParmInt "%1" "%2" "timeout"         7 -1                       && shift && shift && goto :ParmLoop
CALL :isParmInt "%1" "%2" "retry"           5  0                       && shift && shift && goto :ParmLoop
CALL :isParmInt "%1" "%2" "waitUntilStart"  1  0 1                     && shift && shift && goto :ParmLoop
CALL :isParmInt "%1" "%2" "pauseAtEnd"      1  0 1                     && shift && shift && goto :ParmLoop
CALL :isParmInt "%1" "%2" "killOther"       1  0 1                     && shift && shift && goto :ParmLoop
CALL :isParm    "%1" "?"                                               && shift          && goto :Usage    
CALL :isParm    "%1" "h"                                               && shift          && goto :Usage    
CALL :isParm    "%1" "help"                                            && shift          && goto :Usage    
if not "%1"=="" (
  CALL :Print "%1 is an unrecognized or obsolete option."
  shift
  goto :ParmLoop
)

set logErr=con
if not "%log%"=="nul" (
  set logErr=%log%
  set logPS=^|Out-File %log% -Encoding "ASCII" -Width 1024 -Append
)
echo %cmdTitle%>%log%

set scStop=sc stop
set scStart=sc start
set scQuery=sc queryex
set scStopped=STOPPED
set scRunning=RUNNING

set resultStr="Fail. Database %db% was not restored."

:: ------------------------
CALL :printTitle "stop services: %servicesToStop%"
IF not "%servicesToStop%"=="" (
  FOR %%s IN (%servicesToStop%) DO CALL :scStartStop %%s %scStopped% "%scStop%"
  FOR %%s IN (%servicesToStop%) DO CALL :waitUntil %%s %scStopped% %retry%
) ELSE (
  CALL :PrintSkipped
)

CALL :printTitle "stop IIS"
iisreset /stop /status >>%log%&& CALL :PrintOk

CALL :printTitle "Kill other processes that used database %db%"
CALL :PrintOther %db%
IF "%killOther%"=="1" (
  CALL :KillOther %db%
) ELSE (
  CALL :PrintSkipped
)

CALL :printTitle "Restore database %db% from snapshot %snapshot%"
CALL :RestoreDatabase %db% %snapshot%

CALL :printTitle "start services: %servicesToStart%"
IF not "%servicesToStart%"=="" (
  FOR %%s IN (%servicesToStart%) DO CALL :scStartStop %%s %scRunning% "%scStart%"
  IF "%waitUntilStart%"=="1" FOR %%s IN (%servicesToStart%) DO CALL :waitUntil %%s %scRunning% %retry%
) ELSE (
  CALL :PrintSkipped
)

CALL :printTitle "start IIS"
iisreset /start /status >>%log%&& CALL :PrintOk

CALL :printTitle %resultStr%
IF "%pauseAtEnd%"=="1" pause
endlocal
goto :EOF

:: ------------------------
:PrintOther %1 - database name
powershell "$p=invoke-sqlcmd """SELECT spid,rtrim(status) as status,hostprocess as id,rtrim(hostname) as hostname,rtrim(loginame) as login,rtrim(program_name) as program,rtrim(nt_domain)+rtrim(nt_username) as 'user' FROM MASTER..SysProcesses WHERE DBId=DB_ID('%1') AND NOT SPId=@@SPId""";if($p.Count -eq 0){'nothing to kill' %logPs%}else{$p|group status,id,hostname,user,login,program -NoElement|ft -AutoSize %logPs%;$p|where {$_.hostname -eq '%computername%' -and $_.id -ne 0}|ps|ft id, name, product, path %logPs%}"
%exitOk%

:KillOther %1 - database name
sqlcmd -b -Q "DECLARE @SQL varchar(max);SET @SQL='';SELECT @SQL=@SQL+'Kill '+Convert(varchar, SPId)+';' FROM MASTER..SysProcesses WHERE DBId=DB_ID('%1') AND SPId<>@@SPId;EXEC(@SQL)" >>%logErr%|| CALL :PrintFail && %exitFail%
CALL :PrintOk
%exitOk%

:RestoreDatabase from snapshot, %1 - database name, %2 - snapshot name
sqlcmd -b -Q "restore database %1 from Database_snapshot='%2'" >>%logErr%|| CALL :PrintFail && %exitFail%
set resultStr="Ok. Database %1 restored."
CALL :PrintOk
%exitOk%

:scStartStop %1 - service name, %2 - expected status, %3 - command to aproach exected status 
CALL :isSCexists %1|| %exitOk%
CALL :isSCstate %1 %2&& %exitOk%
%~3 %1 >>%log%&& %exitOk%
%exitFail%

:waitUntil %1 - service name, %2 - expected status, %3 - retry count
CALL :isSCexists %1|| CALL :PrintSkipped "%1 is not exists"&& %exitOk%
FOR /L %%r IN (%3,-1,1) DO (
  CALL :isSCstate %1 %2&& CALL :PrintOk "%1 is %2"&& %exitOk%
  CALL :Print "%1 is still not %2. Retry: %%r"
  if not %%r==1 TimeOut %timeout%
)
%exitOk%

:isSCexists %1 - service name
%scQuery% %1 >nul&& %exitOk%
%exitFail%

:isSCstate %1 - service name, %2 - expected status
%scQuery% %1|Find "STATE"|Find "%2">nul&& %exitOk%
%exitFail%





:printTitle
CALL :Print "----"
CALL :Print %1
%exitOk%

:PrintOk
CALL :Print "Ok. %~1"
%exitOk%

:PrintFail
CALL :Print "Fail. %~1"
%exitOk%

:PrintSkipped
CALL :Print "Skipped. %~1"
%exitOk%

:print
ECHO %~1
:log
ECHO [%Date% %Time%]: %~1 >>%log%
%exitOk%





:isParmInt %1 - parm name, %2 - parm value, %3 - keyword, %4 - default value, %5 - min value (optional), %6 - max value (optional)
if not defined %~3 set %~3=%~4
if "%~2"=="" %exitFail%
CALL :isParm %1 %3||%exitFail%
CALL :Validate %2 %5 %6||%exitOk%
set /a %~3=%~2
%exitOk%

:isParmStr %1 - parm name, %2 - parm value, %3 - keyword, %4 - default value
if not defined %~3 set %~3=%~4
if "%~2"=="" %exitFail%
CALL :isParm %1 %3||%exitFail%
set %~3=%~2
if "%~3"=="""" set %~3=
%exitOk%

:isParm %1 - parm name, %2 - keyword
if "%~1"=="" %exitFail%
if "%~2"=="" %exitFail%
for %%a in (.- ./ .) do if /i ".%~1."=="%%a%~2." %exitOk%
%exitFail%

:Validate "%1" - tested value, %2 - min value (optional), %3 - max value (optional)
if "%~1"=="" %exitFail%
if "%~2"=="" %exitOk%
if %~1 LSS %~2 %exitFail%
::is %3 integer
if "%~3"=="" if %~1 GTR 0x7FFFFFFF (%exitFail%) else (%exitOk%)
if %~1 GTR %~3 %exitFail%
%exitOk%





:Usage
echo -----------------------------------------------
echo The restore command requires no other process use the database.
echo This job:
echo   1. stop known services and IIS
echo   2. wait until stopped
echo   3. kill other processes that use database
echo   4. restore database
echo   5. start known services and IIS
echo   6. wait until start
echo -----------------------------------------------
echo   %cmdNameExt% [options] 
echo.
echo Options:
echo   -db             :database name. default=AxDBRAIN
echo   -snapshot       :snapshot name. default=AxDBRAINInitialDataState
echo   -servicesToStop :known service names to stop before the resotre.
echo                    default="%services%"
echo                    empty string "" prevent stop any services.
echo   -killOther      :kill other processes. 0 or 1. default=1
echo   -servicesToStart:known service names to start after the restore.
echo                    default=same as -servicesToStop
echo                    empty string "" prevent start.
echo   -waitUntilStart :wait until start services. 0 or 1. default=1
echo   -log            :log to file. default=nul - no log
echo   -timeout        :timeout in sec to wait. default=7
echo   -retry          :retry count for stop and start. default=5
echo   -pauseAtEnd     :pause this job after complete and wait a user. 0 or 1. default=1
echo   -help -h -?     :This help
echo --------------------------------------------------------
echo Examples:
echo.
echo   %cmdNameExt% -db myDBname -snapshot mySnapshotName
echo   %cmdNameExt% -db myDBname -waitUntilStart 0 -pauseAtEnd 0
echo   %cmdNameExt% -log %cmdName%.log 
echo --------------------------------------------------------
goto :EOF
