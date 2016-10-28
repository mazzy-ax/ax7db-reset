# ax7db-reset

This job restore database from snapshot:
  #. stop known services and IIS
  #. wait until stopped
  #. kill other processes that use database
  #. restore database
  #. start known services and IIS
  #. wait until start

To avoid lost unsaved work the job don't execute steps 'kill other processes' and 'restore' if some known programs (SQL Management Studio, Visual Studio) use database. Close relative queries, object explorers or programs.

Use parameter -h for more help.
see also https://github.com/mazzy-ax/ax7db-reset
