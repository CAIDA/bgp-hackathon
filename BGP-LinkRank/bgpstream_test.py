#!/usr/bin/python

from _pybgpstream import BGPStream, BGPRecord
from collections import defaultdict
from itertools import groupby
import networkx as nx
import radix

# Create a new bgpstream instance and a reusable bgprecord instance
stream = BGPStream()
rec = BGPRecord()

# Create an instance of a simple undirected graph
as_graph = nx.Graph()

bgp_lens = defaultdict(lambda: defaultdict(lambda: None))

# Consider RIS RRC 00 only
stream.add_filter('collector','rrc00')

# Consider RIBs dumps only
stream.add_filter('record-type','ribs')

# Consider this time interval:
# Sat, 01 Aug 2015 7:50:00 GMT -  08:10:00 GMT
stream.add_interval_filter(1438415400,1438416600)

stream.start()

while(stream.get_next_record(rec)):
    elem = rec.get_next_elem()
    while elem:
        # Get the peer ASn
        peer_asn = str(elem.peer_asn)
        peer_asn_ip = elem
        # Get the array of ASns in the AS path and remove repeatedly prepended ASns
        hops = [k for k, g in groupby(elem.fields['as-path'].split(" "))]
        if len(hops) > 1 and hops[0] == peer:
            # Get the origin ASn
            origin = hops[-1]
            # Add new edges to the NetworkX graph
            for i in range(0,len(hops)-1):
                as_graph.add_edge(hops[i],hops[i+1])
            # Update the AS path length between 'peer' and 'origin'
            bgp_lens[peer][origin] = \
                min(filter(bool,[bgp_lens[peer][origin],len(hops)]))
        elem = rec.get_next_elem()


