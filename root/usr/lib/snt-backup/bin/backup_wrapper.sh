#!/bin/bash 

# zet de base-path voor onze scripts..
export BASEDIR='/usr/lib/snt-backup'
export CONFDIR='/etc/snt-backup'

# laad de config
. "${CONFDIR}/config"

# backup disabled?
if [ "_${TODIR}" = _ ]; then
	exit 0
fi

if [ "_${1}" = _backup ]; then
	exec "$BASEDIR"/bin/ssh_wrapper.pl "$BASEDIR"/bin/backup.sh "$@"
else
	exec "$BASEDIR"/bin/backup.sh "$@"
fi
