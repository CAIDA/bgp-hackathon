from _pybgpstream import BGPStream, BGPRecord, BGPElem
from collections import defaultdict
from itertools import groupby


peer_id_dict = dict()
next_peer_id = 1

def get_peerid(collector_name, peer_asn, peer_address):
    global peer_id_dict
    global next_peer_id
    if collector_name not in peer_id_dict:
        peer_id_dict[collector_name] = dict()
    if peer_asn not in peer_id_dict[collector_name]:
        peer_id_dict[collector_name][peer_asn] = dict()
    if peer_address not in peer_id_dict[collector_name][peer_asn]:
        next_peer_id = next_peer_id
        peer_id_dict[collector_name][peer_asn][peer_address] = next_peer_id
        next_peer_id += 1 
    return peer_id_dict[collector_name][peer_asn][peer_address]



# Create a new bgpstream instance and a reusable bgprecord instance
stream = BGPStream()
rec = BGPRecord()

stream.add_filter('project','ris')
stream.add_filter('project','routeviews')

# Consider RIBs dumps only
stream.add_filter('record-type','ribs')

# Consider this time interval:
jan_02_2016 = 1451692800
stream.add_interval_filter(jan_02_2016 - 300, jan_02_2016 + 300)

stream.start()

edge_peer_asn = dict()

while(stream.get_next_record(rec)):
    elem = rec.get_next_elem()

    while(elem):

        # Get the peer IP address
        peer_ip = str(elem.peer_address)

        # Get the peer ASn
        peer_asn = str(elem.peer_asn)

        # Get the array of ASns in the AS path and remove repeatedly prepended ASns
        hops = [k for k, g in groupby(elem.fields['as-path'].split(" "))]
        
        if len(hops) > 1 and hops[0] == peer_asn:

            # get peer id
            peerid = get_peerid(rec.collector, peer_asn, peer_ip)

            # Get the origin ASn
            origin = hops[-1]
            
            # Go through edges
            for i in range(0,len(hops)-1):
                edge  = (hops[i], hops[i+1])

                if not edge in edge_peer_asn:
                    edge_peer_asn[edge] = set()

                # add peer to the set
                edge_peer_asn[edge].add(peerid)

        elem = rec.get_next_elem()

print "#ASN1 ASN2 num_peers_observing_link"
for edge in edge_peer_asn:
    print edge[0], edge[1], len(edge_peer_asn[edge])

# print "Transit:", len(transit)
# print "Edges:", len(edge_peer_asn)
