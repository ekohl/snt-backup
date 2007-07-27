# cron.d/snt-backup - periodieke taken die uitgevoerd worden door de
#                     backup scripts
LOCK='/usr/bin/lock.pl --lockfile /var/lock/.snt-backup'
BACKUP='/usr/lib/snt-backup/bin/backup.sh'

# de weekly en monthly cleanups
10 0 * * 1		root	$LOCK $BACKUP weekly
20 0 1 * *		root	$LOCK $BACKUP monthly

# de backups zelf
30 0 * * *		root	$LOCK $BACKUP backup

# Als je in plaats van een cron mailtje bij errors, een mail wilt hebben 
# met het subject <hostname>: BACKUP OK of BACKUP WARNINGS, uncomment dan 
# de volgende twee regels, en comment de regel hier boven uit. Zet vervolgens
# In /etc/snt-backup/config REPORT_ALWAYS="yes"
#MAILTO=""
#30 0 * * *       root  OUTFILE="/tmp/snt-backup-$RANDOM"; (HOSTNAME=`hostname`; . /etc/snt-backup/config; $LOCK $BACKUP backup > $OUTFILE && (if [ "${REPORT_ALWAYS}x" = "yesx" ]; then cat $OUTFILE | mailx -s "$HOSTNAME: BACKUP OK" root; fi; exit 0) || (cat $OUTFILE | mailx -s "$HOSTNAME: BACKUP WARNINGS" root; exit 0;);); rm -f $OUTFILE
