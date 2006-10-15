#!/bin/sh

set -e

KEYSIZE=512

# don't overwrite keys!
if [ -e /etc/snt-backup/rsakey.pub ]
then
	echo "Remove /etc/snt-backup/rsakey.pub first!"
	exit 1
fi

if [ -e ./snt-backup-rsakey ]
then
	echo "Remove ./snt-backup-rsakey first!"
	exit 1
fi

umask 077

# build rsa key (should be done once..)
RND=`tempfile`

dd if=/dev/urandom of="$RND" bs=1024 count=1024 2> /dev/null
openssl genrsa -rand "$RND" -out ./snt-backup-rsakey $KEYSIZE
openssl rsa -in ./snt-backup-rsakey -pubout -out /etc/snt-backup/rsakey.pub
rm -f "$RND"

chmod 400 ./snt-backup-rsakey

echo "Public RSA key saved to /etc/snt-backup/rsakey"
echo "Private RSA key saved to ./snt-backup-rsakey (only needed for decryption)"
