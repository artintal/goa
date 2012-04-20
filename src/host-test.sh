#!/bin/bash
#
# Copyright (C) 2012  Eric Schulte
#
# Usage:
#   host-test.sh variant.s
#
# Commentary:
#   This does not follow the normal test script format but rather it;
#    1. takes the path to a .s asm file
#    2. copies that file to a VM
#    3. runs the resulting program in Graphite in the VM
#    4. returns the full set of Graphite debug information in a format
#       readable by the common lisp `read-from-string' function.
#
# Code:
REMOTES=("2222")
LIMIT="$(dirname $0)/limit"
. $(dirname $0)/REMOTES # allow host-specific remote files
pick_remote(){ echo ${REMOTES[$RANDOM % ${#REMOTES[@]}]}; }

if [ -z "$1" ];then echo "requires an argument"; exit 1;fi
var=$1
guest_test="/home/bacon/bin/guest-test.sh"
cmd="$guest_test /tmp/$(basename $var)"
id="../data/id_rsa"
output_path="graphite/output_files/sim.out"

## run remotely and collect output and return value
output="busy"
while [ "$output" = "busy" ]; do
    remote=$(pick_remote)
    $LIMIT scp -i $id -P $remote $var bacon@localhost:/tmp/ >/dev/null
    output=$($LIMIT ssh -t -i $id -p $remote bacon@localhost "$cmd" 2>/dev/null)
    if [ "$output" = "busy" ];then sleep 1; fi
done

## if successful collect the output file
log_output=$($LIMIT scp -i $id -P $remote bacon@localhost:$output_path /dev/stdout)

## return the execution metrics as lisp
sed_cmd=$(cat <<EOF
s/://;
s/ \+/ /g;
s/Start time/start/;
s/Initialization finish time/init-finish/;
s/Overall finish time/finish/;
s/Total time with initialization/time-w-init/;
s/Total time without initialization/time-wo-init/;
s/Overall transpose time/trans-time/;
s/Overall transpose fraction/trans-fraction/;
EOF
)
log_sed_cmd=$(cat <<EOF
s/^ \+//;
s/ \+| \+/ /g;
s/(//g;
s/)//g;
s/\([a-zA-Z]\) \([a-zA-Z]\)/\1-\2/g;
EOF
)

# runtime metrics
echo "$output" \
    |sed -n '/FFT with Blocking Transpose/,$p' \
    |egrep " : +[.0-9]+"|sed "$sed_cmd"

# collecting the "Network model 2" stats
echo "$log_output" \
    |sed -n '/Network model 2/,/Network model 3/p' \
    |grep -v 'Network model'|grep -v 'Activity Counters' \
    |sed "$log_sed_cmd"

# success
echo "$output"|grep "Exited with return code: 0" >/dev/null 2>/dev/null && exit 0
exit 1
