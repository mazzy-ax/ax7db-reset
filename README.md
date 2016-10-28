# ax7db-reset

This job restore database from snapshot:
1. stop known services and IIS
2. wait until stopped
3. kill other processes that use database
4. restore database
5. start known services and IIS
6. wait until start

To avoid lost unsaved work the job don't execute steps 'kill other processes' and 'restore' if some known programs (SQL Management Studio, Visual Studio) use database. Close relative queries, object explorers or programs.

Use parameter -h for more help.
see also https://github.com/mazzy-ax/ax7db-reset
