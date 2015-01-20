# svnbackup
Simple svn backup script

The main objective is to have small, portable script (no PERL or Pyton) with the most comprehensive error checking possible for a crontab-scheduled backup

1. batch (non-interactive) execution: no user input is required and any error can be checked with errorlevel returned value
2. comprehensive error checking: error are checked during any file system access and the resulting backup is tested for consistency. Control file is updated only if the backup is successful
3. avoid unnecessary backups: no backup is created if the repository is not changed

