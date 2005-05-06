#! /bin/sh

/usr/bin/find ./md5s/ -type l -xtype f | sed 's/^\.\/md5s\///' | sort -u
