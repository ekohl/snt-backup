#! /bin/sh

file="$1"
exec 1> "$file".report 2>&1

echo "Filename '$file'"
echo

CNT_BYTES="`ls -ald "$file" | sed 's/  */ /g' | cut -d' ' -f5`"

echo "Bestandsgrootte   : $CNT_BYTES"
echo

if [ "$CNT_BYTES" = 0 ]; then
	echo "Empty ?" 2>> "$file".errors
fi

case "$file" in
	*.tar.gz | *.tgz)
		tar --blocking-factor=1 -ztvf "$file" > "$file".list 2>> "$file".errors

		CNT_DIRS="`grep -c '/$' "$file".list`"
		CNT_FILES="`grep -vc '/$' "$file".list`"

		echo "Aantal directories: $CNT_DIRS"
		echo "Aantal bestanden  : $CNT_FILES"
		echo

		;;

	*.tar.bz2)
		tar --blocking-factor=1 -jtvf "$file" > "$file".list 2>> "$file".errors

		CNT_DIRS="`grep -c '/$' "$file".list`"
		CNT_FILES="`grep -vc '/$' "$file".list`"

		echo "Aantal directories: $CNT_DIRS"
		echo "Aantal bestanden  : $CNT_FILES"
		echo

		;;

	*.gz)
		gzip -t "$file" 2>> "$file".errors
		;;

	*.bz2)
		bzip2 -t "$file" 2>> "$file".errors
		;;
esac

if [ -s "$file".errors ]
then
	echo "Bij testen van de backup is een fout opgetreden:"
	cat "$file".errors
	SUBJECT="FAILED backup '$file'"
else
	echo "Backup OK"
	rm -f "$file".errors
	SUBJECT="Backupped file '$file'"

	if [ -d "../md5s" ]
	then
		case "$file" in
			*.gz)
				ln -fs ../backups/"$file" ../md5s/"`gunzip < "$file" 2> /dev/null | md5sum | tr -d '\\n'`"
				;;

			*.bz2)
				ln -fs ../backups/"$file" ../md5s/"`bunzip2 < "$file" 2> /dev/null | md5sum | tr -d '\\n'`"
				;;

			*)
				ln -fs ../backups/"$file" ../md5s/"`md5sum < "$file" | tr -d '\\n'`"
				;;
		esac
	fi
fi

USERNAME="`grep "^$USER:" /etc/passwd | cut -d: -f5 | cut -d, -f1`"

if [ -s "$file".errors ]
then
(
	echo "From: \"Backup Daemon\" <root>"
	echo "To: \"$USERNAME\" <$USER>"
	echo "Subject: $SUBJECT"
	echo
	cat "$file".report
) | ( cd / && /usr/lib/sendmail "$USER" )
fi
