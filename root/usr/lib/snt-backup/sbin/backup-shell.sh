#! /bin/bash
# Author     : Robbet Müller <muller@snt.utwente.nl>
#
# Description: Rwrapper around perl script sets all configuration in the enviroment

export BASEDIR='/usr/lib/snt-backup'
export CONFDIR='/etc/snt-backup'
. ${CONFDIR}/server/server.conf

exec "${BASEDIR}/sbin/backup-shell.pl" "$@"

