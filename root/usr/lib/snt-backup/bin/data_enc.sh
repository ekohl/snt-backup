#!/bin/sh

set -e

# build blowfish key
BF_KEY=`tempfile`

{
  dd if=/dev/urandom bs=1024 count=1 2> /dev/null |
    tr -d '\0- \177-\377' |
    dd bs=31 count=1 2> /dev/null
	echo
} > "$BF_KEY"

# send blowfish key, encrypted with rsa key
openssl rsautl -inkey /etc/snt-backup/rsakey.pub -pubin -encrypt -in "$BF_KEY"

# send data, encrypted with blowfish key
openssl enc -e -bf-cbc -pass file:"$BF_KEY" -salt

# cleanup
rm -f "$BF_KEY"
