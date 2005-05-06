#! /bin/sh

/usr/bin/find ./md5s/ -type l ! -xtype f -print0 | xargs -0 --no-run-if-empty rm -f --
