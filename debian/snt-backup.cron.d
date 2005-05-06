# cron.d/snt-backup - periodieke taken die uitgevoerd worden door de
#                     backup scripts
LOCK='/usr/bin/lock.pl --lockfile /var/lock/.snt-backup'
BACKUP='/usr/lib/snt-backup/bin/backup.sh'

# de weekly en monthly cleanups
10 0 * * 1		root	$LOCK $BACKUP weekly
20 0 1 * *		root	$LOCK $BACKUP monthly

# de backups zelf
30 0 * * *		root	$LOCK $BACKUP backup
