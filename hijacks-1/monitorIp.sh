#!/bin/bash
while read p; do
    ping -c 1 -W 1 $p >/dev/null
    echo $?
done < alexa-top-100.txt
