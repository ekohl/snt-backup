#!/bin/bash 

# zet de base-path voor onze scripts..
export BASEDIR='/usr/lib/snt-backup'
export CONFDIR='/etc/snt-backup'

# $FUNC	-	gedefinieerde functies:
#			- backup	het maken van een backup
#			- weekly	voor wekelijkse cleanups e.d.
#			- monthly	voor maandelijkse cleanups e.d.
#
export FUNC='backup'

if [ "${#}" != 1 -o "_${1}" = "_-h" -o "_${1}" = "_--help" ]
then
	echo "Usage: ${0} [ backup | weekly | monthly ]" >&2
	exit 1
fi

case "${1}" in
	backup)
		export FUNC='backup'
		;;
	weekly)
		export FUNC='weekly'
		;;
	monthly)
		export FUNC='monthly'
		;;
	*)
		echo "Unknown command '${1}'!" >&2
		exit 1;
		;;
esac

umask 077

# default settings
export COMPRESS=''
export C_TAG=''

export ENCRYPT=''
export E_TAG=''

# laad de config en standaard modules in
. "${CONFDIR}/config"
. "${BASEDIR}/lib/base"

# cd to snapshotdir
cd "${SNAPSHOTDIR}" || exit 1

if [ "$FUNC" = "weekly" ]; then
	if [ -z "$DAY_WEEKLY_CLEANUP" ]; then
		DOW=1
	elif [ "$DAY_WEEKLY_CLEANUP" = "monday" ]; then
		DOW=1
	elif [ "$DAY_WEEKLY_CLEANUP" = "tuesday" ]; then
		DOW=2
	elif [ "$DAY_WEEKLY_CLEANUP" = "wednesday" ]; then
		DOW=3
	elif [ "$DAY_WEEKLY_CLEANUP" = "thursday" ]; then
		DOW=4
	elif [ "$DAY_WEEKLY_CLEANUP" = "friday" ]; then
		DOW=5
	elif [ "$DAY_WEEKLY_CLEANUP" = "saturday" ]; then
		DOW=6
	elif [ "$DAY_WEEKLY_CLEANUP" = "sunday" ]; then
		DOW=7
	else
		echo "Invalid 'DAY_WEEKLY_CLEANUP'." >&2
		exit 1
	fi

	# check day of week
	if [ `date +%u` -ne $DOW ]; then
		exit 0
	fi
fi

# reset de error flag..
rm -f "${SNAPSHOTDIR}/error"

(
	if [ "${LOAD_PLUGINS}x" = "x" ]; then
			# Als niet gedefinieerd is welke plugins we willen laden,
			# dan laden we ze allemaal automagisch
			# som alle uitvoerbare plugins in de plugins dir op.. (met +x)
			PLUGINS="`cd "${BASEDIR}/plugins" && find . -type f -perm +100 -a ! -name '*.dpkg-*' | sed 's|^\./||'`"
	else
		# Anders halen we het uit de config
		PLUGINS=""
		for plugin in ${LOAD_PLUGINS}; do
				if [ ! -x ${BASEDIR}/plugins/${plugin} ]; then
						echo "Error: Plugin ${plugin} not found" 1>&2
			touch "${SNAPSHOTDIR}/error"
				else
					PLUGINS="${PLUGINS} ${plugin}"
				fi
		done
	fi

	# laad alle scripts in
	for plugin in ${PLUGINS}; do
		echo "Loading plugin '${plugin}'."
		. "${BASEDIR}/plugins/${plugin}"
	done
		
	# en voer de juiste functie uit
	for plugin in ${PLUGINS}; do
		if [ "_${FUNC}" = '_backup' ] && [ "`eval "echo -n \\\$PRE_${plugin}"`" ]; then
			echo "Running pre-${plugin} script."
			eval "\$PRE_${plugin}"
		fi

		echo "Running plugin '${plugin}'."
		"`echo "${plugin}" | sed 's|/|_|g'`_${FUNC}"

		if [ "_${FUNC}" = '_backup' ] && [ "`eval "echo -n \\\$POST_${plugin}"`" ]; then
			echo "Running post-${plugin} script."
			eval "\$POST_${plugin}"
		fi
	done

)	1> "${SNAPSHOTDIR}/${DATEFIX}-stdout" \
	2> "${SNAPSHOTDIR}/${DATEFIX}-stderr"

# is de error-flag geset?
if [ -e "${SNAPSHOTDIR}/error" -o -s "${SNAPSHOTDIR}/${DATEFIX}-stderr" ]; then
	ERROR=1
else
	ERROR=0
fi

if [ $ERROR = 1 -o "`echo ${REPORT_ALWAYS} | tr A-Z a-z`x" = "yesx" ]; then

	echo "Stdout:"
	cat "${SNAPSHOTDIR}/${DATEFIX}-stdout"
	echo
	echo "Stderr:"
	cat "${SNAPSHOTDIR}/${DATEFIX}-stderr"
fi

# ruim wat troep op...
rm -f	"${SNAPSHOTDIR}/${DATEFIX}-stdout" \
		"${SNAPSHOTDIR}/${DATEFIX}-stderr" \
		"${SNAPSHOTDIR}/error"

exit $ERROR
