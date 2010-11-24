#!/bin/bash

do_test() {
	sleep 0.$[ $RANDOM + 1000000 ]
	../root/usr/bin/lock.pl sh -c 'echo -n h; echo -n e; echo -n l; echo -n l; echo -n o; echo'
}

do_fork_1() {
	do_test & do_test &
	wait
}

do_fork_2() {
	do_fork_1 & do_fork_1 &
	wait
}

do_fork_3() {
	do_fork_2 & do_fork_2 &
	wait
}

do_fork_4() {
	do_fork_3 & do_fork_3 &
	wait
}

do_fork_5() {
	do_fork_4 & do_fork_4 &
	wait
}

do_fork_6() {
	do_fork_5 & do_fork_5 &
	wait
}

do_fork_m() {
	for i in `seq 150`; do
		do_test &
	done
	wait
}

renice +20 $$ > /dev/null

for j in `seq 25`; do
	echo "[$j]"
	do_fork_m | grep -v '^hello$'
done
