#! /bin/sh

export BASEDIR='/usr/lib/snt-backup'
export CONFDIR='/etc/snt-backup'

. ${CONFDIR}/server/server.conf

if [ "${BACKUP_LOCATION}x" = "x" ]; then BACKUP_LOCATION='/backups'; fi
if [ "${NO_ACT}x" = "yesx" ]; then FLAGS="${FLAGS} --no-act"; fi
if [ "${VERBOSE}x" = "yesx" ]; then FLAGS="${FLAGS} --verbose"; fi
if [ "${REPORT}x" = "yesx" ]; then FLAGS="${FLAGS} --report"; fi
if [ "${RETENTION_PERIOD_DAILY}x" != "x" ]; then FLAGS="${FLAGS} --retention_period_daily=${RETENTION_PERIOD_DAILY}"; fi
if [ "${RETENTION_PERIOD_MONTHLY}x" != "x" ]; then FLAGS="${FLAGS} --retention_period_monthly=${RETENTION_PERIOD_MONTHLY}"; fi
if [ "${RETENTION_PERIOD_YEARLY}x" != "x" ]; then FLAGS="${FLAGS} --retention_period_yearly=${RETENTION_PERIOD_YEARLY}"; fi

cd ${BACKUP_LOCATION} || exit 1

for i in */backups
do
	(
	        if [ ! -e "${i}/CLEANUP_DISABLE" ]; then 
  		        #echo "Cleaning $i..."
		        cd "$i" && ${BASEDIR}/sbin/cleanup.pl ${FLAGS}
		fi
	)
done
