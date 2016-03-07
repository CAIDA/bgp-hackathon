#!/bin/bash

if [ $# -lt 4 ]; then
    echo "Usage: $0 <ID> <IP> <AS> <bird_config_file>";
    exit;
fi

ID=$1;
NEIGHBOR_IP=$2
NEIGHBOR_AS=$3
BIRD_CFG_FILE=$4

echo -e "\nprotocol bgp $ID {" >> $BIRD_CFG_FILE;
echo -e "\tdescription \"$ID\";" >> $BIRD_CFG_FILE;
echo -e "\tdebug all;" >> $BIRD_CFG_FILE;
echo -e "\texport none;" >> $BIRD_CFG_FILE;
echo -e "\tkeepalive time 30;" >> $BIRD_CFG_FILE;
echo -e "\thold time 60;" >> $BIRD_CFG_FILE;
echo -e "\timport all;" >> $BIRD_CFG_FILE;
echo -e "\tneighbor $NEIGHBOR_IP as $NEIGHBOR_AS;" >> $BIRD_CFG_FILE;
echo -e "\tmultihop 5;" >> $BIRD_CFG_FILE;
echo -e "\tlocal as 65517;" >> $BIRD_CFG_FILE;
echo -e "\tnext hop self;" >> $BIRD_CFG_FILE;
echo -e "}" >> $BIRD_CFG_FILE;


