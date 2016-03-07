from _pybgpstream import BGPStream, BGPRecord, BGPElem
from collections import defaultdict
from itertools import groupby

# Create a new bgpstream instance and a reusable bgprecord instance
stream = BGPStream()
rec = BGPRecord()

# Consider RIS RRC 00 only
stream.add_filter('collector','route-views.sfmix')

# Consider RIBs dumps only
stream.add_filter('record-type','ribs')

# Consider this time interval:
jan_02_2016 = 1451692800
stream.add_interval_filter(jan_02_2016 - 300, jan_02_2016 + 300)

stream.start()

tier1_str = "174 209 286 701 1239 1299 2828 2914 3257 3320 3356 5511 6453 6461 6762 7018 12956"
tier1s = tier1_str.split()

edge_pfx = dict()
transit = set()



while(stream.get_next_record(rec)):
    elem = rec.get_next_elem()
    while(elem):

        # Get the peer IP address
        peer_ip = str(elem.peer_address)

        # Get the peer ASn
        peer_asn = str(elem.peer_asn)

        # Get the array of ASns in the AS path and remove repeatedly prepended ASns
        hops = [k for k, g in groupby(elem.fields['as-path'].split(" "))]
        
        if len(hops) > 3 and hops[0] == peer_asn:
            
            # Get the origin ASn
            origin = hops[-1]
            
            # Go through edges
            for i in range(1,len(hops)-2):
                edge  = (hops[i], hops[i+1])
                transit.add(hops[i])
                transit.add(hops[i+1])

                if not edge in edge_pfx:
                    edge_pfx[edge] = set()

                # add peer to the set
                edge_pfx[edge].add(elem.fields["prefix"])

        elem = rec.get_next_elem()

for edge in edge_pfx:
    if edge[0] not in tier1s and edge[1] not in tier1s:
        print ",".join([edge[0], edge[1], str(len(edge_pfx[edge])), "not1"])
    else:
        if edge[0] not in tier1s or edge[1] not in tier1s:
            print  ",".join([edge[0], edge[1], str(len(edge_pfx[edge])), "involvingt1"])
        else:
            print  ",".join([edge[0], edge[1], str(len(edge_pfx[edge])), "tier1"])

# print "Transit:", len(transit)
# print "Edges:", len(edge_peer_asn)
