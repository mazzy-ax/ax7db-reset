@echo off
setlocal

set exitFail=EXIT /b 1
set exitOk=EXIT /b 0

SET cmdName=%~n0
SET cmdNameExt=%~n0%~x0
SET cmdPath=%~p0
SET cmdTitle=%cmdNameExt%: Restore databse from the snapshot. mazzy, v2016-09-26
TITLE %cmdTitle%

ECHO.
ECHO %cmdTitle%
ECHO Use parameter -h for more help. see also https://github.com/mazzy-ax/ax7db-reset

CALL :ParmLoop %*
CALL :Validate "%db%"                 ||set db=AxDBRAIN
CALL :Validate "%snapshot%"           ||set snapshot=AxDBRAINInitialDataState
CALL :Validate "%servicesToStop%"     ||set servicesToStop=DynamicsAxBatch MR2012ProcessService Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe MSSQLServerOLAPService ReportServer
CALL :Validate "%servicesToStart%"    ||set servicesToStart=%servicesToStop%
CALL :Validate "%log%"                ||set log=nul
CALL :Validate "%logErr%"             ||set logErr=con
CALL :Validate "%resultStr%"          ||set resultStr=***
CALL :Validate "%timeout%"       -1   ||set /a timeout=7
CALL :Validate "%retry%"          0   ||set /a retry=5
CALL :Validate "%killOther%"      0 1 ||set /a killOther=1
CALL :Validate "%waitUntilRun%"   0 1 ||set /a waitUntilRun=1
CALL :Validate "%pauseAtEnd%"     0 1 ||set /a pauseAtEnd=1
IF "%servicesToStop%"=="""" set servicesToStop=
IF "%servicesToStart%"=="""" set servicesToStart=

set sqlcmd=sqlcmd -b -Q

set iisStop=iisreset /stop /status
set iisStart=iisreset /start /status

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
%iisStop% >>%log%&& CALL :PrintOk

CALL :printTitle "Kill other processes that used database %db%"
IF "%killOther%"=="1" (
  CALL :KillOther
) ELSE (
  CALL :PrintSkipped
)

CALL :printTitle "Restore database %db%"
CALL :RestoreDatabase

CALL :printTitle "start services: %servicesToStart%"
IF not "%servicesToStart%"=="" (
  FOR %%s IN (%servicesToStart%) DO CALL :scStartStop %%s %scRunning% "%scStart%"
  IF "%waitUntilRun%"=="1" FOR %%s IN (%servicesToStart%) DO CALL :waitUntil %%s %scRunning% %retry%
) ELSE (
  CALL :PrintSkipped
)

CALL :printTitle "start IIS"
%iisStart% >>%log%&& CALL :PrintOk

CALL :printTitle %resultStr%
IF "%pauseAtEnd%"=="1" pause
endlocal
EXIT

:: ------------------------
:KillOther
%sqlcmd% "DECLARE @SQL varchar(max);SET @SQL='';SELECT @SQL=@SQL+'Kill '+Convert(varchar, SPId)+';' FROM MASTER..SysProcesses WHERE DBId=DB_ID('%db%') AND SPId<>@@SPId;EXEC(@SQL)" >>%logErr%|| CALL :Print "Fail."&& %exitFail%
CALL :PrintOk
%exitOk%

:RestoreDatabase from snapshot
%sqlcmd% "restore database %db% from Database_snapshot='%snapshot%'" >>%logErr%|| CALL :Print "Fail."&& %exitFail%
set resultStr="Ok. Database %db% restored."
CALL :PrintOk
%exitOk%

:scStartStop %1 - service name, %2 - expected status, %3 - command to aproach exected status 
CALL :isSCexists %1|| %exitOk%
CALL :isSCstate %1 %2&& %exitOk%
%~3 %1 >>%log%&& %exitOk%
%exitFail%

:waitUntil %1 - service name, %2 - expected status, %3 - retry count
CALL :isSCexists %1|| CALL :Print "Fail. %1 is not exists"&& %exitOk%
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

:PrintSkipped
CALL :Print "Skipped. %~1"
%exitOk%

:print
ECHO %~1
:log
ECHO %Date% %Time%: %~1 >>%log%
%exitOk%

:Validate "%1" - tested value, %2 - min value (optional), %3 - max value (optional)
if "%~1"=="" %exitFail%
if "%~2"=="" %exitOk%
if %~1 LSS %~2 %exitFail%
::is integer
if "%~3"=="" if %~1 GTR 0x7FFFFFFF %exitFail% 
if %~1 GTR %~3 %exitFail%
%exitOk%

:ParmLoop
if "%1"=="" goto :ParmLoopEnd

  :: Usage (-?, -h, -help)
  for %%a in (./ .- .) do if /i ".%1." == "%%a?." goto :Usage    
  for %%a in (./ .- .) do if /i ".%1." == "%%ah." goto :Usage    
  for %%a in (./ .- .) do if /i ".%1." == "%%ahelp." goto :Usage    

  :: database name. (-db)
  for %%a in (./ .- .) do if /i ".%1." == "%%adb." ( Set db=%2& shift& shift& goto :ParmLoop )

  :: snapshot name (-snapshot)
  for %%a in (./ .- .) do if /i ".%1." == "%%asnapshot." ( Set snapshot=%2& shift& shift& goto :ParmLoop )

  :: services to stop (-serivesToStop)
  for %%a in (./ .- .) do if /i ".%1." == "%%aservicestostop." ( Set servicesToStop=%2& shift& shift& goto :ParmLoop )

  :: services to start (-serivesToStart)
  for %%a in (./ .- .) do if /i ".%1." == "%%aservicestostart." ( Set servicesToStart=%2& shift& shift& goto :ParmLoop )

  :: kill other processes (-ko, -killOther)
  for %%a in (./ .- .) do if /i ".%1." == "%%akillother." ( Set /a killOther=%2& shift& shift& goto :ParmLoop )
  for %%a in (./ .- .) do if /i ".%1." == "%%ko." ( Set /a killOther=%2& shift& shift& goto :ParmLoop )

  :: log to files (-log)
  for %%a in (./ .- .) do if /i ".%1." == "%%alog." ( Set log=%2& Set logErr=%2& ECHO %cmdTitle%>%2& shift& shift& goto :ParmLoop )

  :: wait until run  (-waitUntilRun)
  for %%a in (./ .- .) do if /i ".%1." == "%%awaituntilrun." ( Set /a waitUntilRun=%2& shift& shift& goto :ParmLoop )

  :: pause at end  (-pauseAtEnd)
  for %%a in (./ .- .) do if /i ".%1." == "%%apauseatend." ( Set /a pauseAtEnd=%2& shift& shift& goto :ParmLoop )

  :: timeout in sec (-timeout)
  for %%a in (./ .- .) do if /i ".%1." == "%%atimeout." ( Set /a timeOut=%2& shift& shift& goto :ParmLoop )

  :: retry count (-retry)
  for %%a in (./ .- .) do if /i ".%1." == "%%aretry." ( Set /a retry=%2& shift& shift& goto :ParmLoop )

  echo %1 is an unrecognized or obsolete option.& shift
  timeout %timeout%
  goto :ParmLoop

:ParmLoopEnd
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
echo   6. wait until run
echo -----------------------------------------------
echo   %cmdNameExt% [options] 
echo.
echo Options:
echo   -db             :database name. default=AxDBRAIN
echo   -snapshot       :snapshot name. default=AxDBRAINInitialDataState
echo   -servicesToStop :known service names to stop before the resotre.
echo                    empty string "" prevent stop any services.
echo                    default="DynamicsAxBatch MR2012ProcessService Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService.exe MSSQLServerOLAPService ReportServer"
echo   -servicesToStart:known service names to start after the restore.
echo                    empty string "" prevent start.
echo                    default=same as -servicesToStop
echo   -killOther      :kill other processes. 0/1(default). alias -ko
echo   -log            :log to file. default=nul - no log
echo   -waitUntilRun   :wait until run known services. 0/1(defaul)
echo   -timeout        :timeout in sec to wait. default=7
echo   -retry          :retry count for stop and start
echo   -pauseAtEnd     :pause this job after complete and wait a user. 0/1(default)
echo   -?              :This help
echo --------------------------------------------------------
echo Examples:
echo.
echo   %cmdNameExt% -db myDBname -snapshot mySnapShotname
echo   %cmdNameExt% -db myDBname -waitUntilRun 0 -pauseAtEnd 0
echo   %cmdNameExt% -log %cmdName%.log 
echo   %cmdNameExt% -log
echo --------------------------------------------------------
exit