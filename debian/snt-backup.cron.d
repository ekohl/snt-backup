# cron.d/snt-backup - periodieke taken die uitgevoerd worden door de
#                     backup scripts
LOCK='/usr/bin/lock.pl --lockfile /var/lock/.snt-backup'
BACKUP='/usr/lib/snt-backup/bin/backup_wrapper.sh'

# de weekly en monthly cleanups
10 0 * * *		root	$LOCK $BACKUP weekly
20 0 1 * *		root	$LOCK $BACKUP monthly

# de backups zelf
30 0 * * *		root	$LOCK $BACKUP backup

# Als je in plaats van een cron mailtje bij errors, een mail wilt hebben 
# met het subject <hostname>: BACKUP OK of BACKUP WARNINGS, uncomment dan 
# de volgende twee regels, en comment de regel hier boven uit. Zet vervolgens
# In /etc/snt-backup/config REPORT_ALWAYS="yes"
#30 0 * * *		root	/usr/lib/snt-backup/bin/mail_wrapper.sh
