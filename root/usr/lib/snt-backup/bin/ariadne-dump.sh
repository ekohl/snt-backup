#!/bin/bash

set -e

ARIADNE="${1}"
DUMPDIR="${2}"
REFFILE="${3}"

if [ \
	-z "${ARIADNE}" -o \
	-z "${DUMPDIR}" -o \
	-z "${REFFILE}" \
	] ; then 
	echo 'argumenten zijn stuk' 1>&2 
	exit
fi


/usr/lib/snt-backup/bin/ariadne-dump.php "${ARIADNE}" "${DUMPDIR}"  &&
date +%s > ${REFFILE}
