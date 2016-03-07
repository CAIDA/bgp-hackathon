#!/bin/bash

start_ts=1448928000
interval=3600
nbproc=31

for i in `seq 0 $nbproc`;
do
    start_tmp=$(($start_ts+($i*$interval)))
    end_tmp=$(($start_tmp+$interval))
    echo python MyBGPStream.py -s $start_tmp -e $end_tmp &
    python MyBGPStream.py -s $start_tmp -e $end_tmp &
done

