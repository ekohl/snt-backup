#! /bin/sh

cd /backups || exit 1

cat << _EOF_
Voor degenen die dit lezen,

Ik heb een script geschreven dat oude backup files weggooit.
Output van dit script wordt nu via deze cron-mail naar jou,
root, toe gestuurd, om te kunnen controleren of de backup
cleanups naar behoren draaien.

Bas van Sisseren
------------------------------------------------------------
_EOF_

for i in */backups
do
	(
		echo "Cleaning $i..."
		cd "$i" &&
		/backups/bin/cleanup.pl
	)
done
echo '------------------------------------------------------------'
echo
echo '-- '
echo 'Real men don'\''t use backups, they post their stuff on a public'
echo 'ftp server and let the rest of the world make copies.'
