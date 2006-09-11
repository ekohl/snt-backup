# cron.d/snt-backup-server
#                     - periodieke taken die uitgevoerd worden op de
#                     backup server

LOCK='/usr/bin/lock.pl --lockfile /var/lock/.snt-backup-server'
CLEANUP='/usr/lib/snt-backup/sbin/cleanup.sh'

# de backups zelf
59 23 * * *		root	$LOCK $CLEANUP
