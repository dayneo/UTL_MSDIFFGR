set srcdir=%~dp0source
set builddir=%~dp0build
set scriptname=msdiffgr.sql

mkdir "%builddir%"

type "%srcdir%\UTL_MSDIFFGR.pks" >  "%builddir%\%scriptname%"
ECHO.                            >> "%builddir%\%scriptname%"
type "%srcdir%\UTL_MSDIFFGR.pkb" >> "%builddir%\%scriptname%"
ECHO.                            >> "%builddir%\%scriptname%"
