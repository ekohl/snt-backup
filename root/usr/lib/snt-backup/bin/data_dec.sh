#!/bin/sh

set -e

KEYSIZE=512

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <keyfile>" >&2
	exit 1
fi

# decrypt key
BF_KEY=`tempfile`
RSAKEY="$1"

dd bs=$(( $KEYSIZE / 8 )) count=1 2> /dev/null |
	openssl rsautl -inkey "$RSAKEY" -decrypt > "$BF_KEY"

# decrypt data
openssl dec -d -bf-cbc -pass file:"$BF_KEY" -salt

# cleanup
rm -f "$BF_KEY"
