#!/bin/bash

BGPASN=65517

if [ $# -lt 4 ]; then
	echo "Error in parameters\nUsage: <Neighbor IP> <Remote AS> <Multihop distance> <Router ID> <Protocol>\n"
	exit 1
fi

NEIGHIP=$1
REMAS=$2
MULTIHOP=$3
ROUTERID=$4
PROTOCOL=$5

QUAGGASTR="test\nena\nconf t\nrouter bgp $BGPASN\nbgp router-id $ROUTERID\nneighbor $NEIGHIP remote-as $REMAS\nneighbor $NEIGHIP ebgp-multihop $MULTIHOP\n"

if [[ "$PROTOCOL" == "IPv6" ]];
then
	QUAGGASTR=$QUAGGASTR"\nno neighbor $NEIGHIP activate\naddress-family ipv6 unicast\nneighbor $NEIGHIP activate\nexit\n"
fi

QUAGGASTR=$QUAGGASTR"\nexit\nexit\nexit\nexit"

echo -e $QUAGGASTR | nc localhost bgpd 

