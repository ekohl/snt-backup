#!/bin/bash

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

TMPAX="`mktemp -d /var/tmp/ariadne_tmp_XXXXXX`" || { echo "couldn't create tmp file" 1>&2 ; exit 1 ; }

cd ${TMPAX}
tar -zcf - .
rmdir ${TMPAX}


