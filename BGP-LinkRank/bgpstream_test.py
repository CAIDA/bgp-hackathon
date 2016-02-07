#!/usr/bin/env python

from _pybgpstream import BGPStream, BGPRecord, BGPElem
import datetime, pytz
import collections
from radix import radix
from socket import (getaddrinfo, gaierror,
                    inet_pton, inet_ntop, AF_INET, AF_INET6, SOCK_RAW,
                    AI_NUMERICHOST)

class BGPCollectorStream():

    collector_name = ""
    peer_trie_handles = {}
    aslink_datastore = {}

    def __init__(self, collector_name = "route-views.sfmix"):
        self.collector_name = collector_name
        self.peer_trie_handles = collections.defaultdict(radix.Radix)
        self.aslink_datastore = collections.defaultdict(dict)

    def create_trie_from_bgpstream_info(self, interval_start=1451692800):

        stream = BGPStream()
        rec = BGPRecord()

        stream.add_filter('collector', self.collector_name)
        stream.add_filter('record-type', 'ribs')

        if isinstance(interval_start, datetime.datetime):
            interval_start_utc = self.convert_interval_to_utc(interval_start)
            stream.add_interval_filter(interval_start_utc - 300, interval_start_utc + 300)
        else:
            stream.add_interval_filter(interval_start - 300, interval_start + 300)

        stream.start()

        while (stream.get_next_record(rec)):
            elem = rec.get_next_elem()
            while elem:
                # Get the peer ASN and IP. We then construct a peer_id, since a collector
                # can establish multiple connections with the same ASN.
                peer_asn = elem.peer_asn
                peer_asn_ip = elem.peer_address

                # make this an unmodifiable tuple
                peer_id = (peer_asn, peer_asn_ip)

                peer_route_trie = self.peer_trie_handles[peer_id]
                trie_node = peer_route_trie.add(elem.fields['prefix'])
                trie_node.data['as-path'] = elem.fields['as-path']
                elem = rec.get_next_elem()

    def convert_interval_to_utc(self, interval=None):
        '''
        This method converts a time interval to UTC
        :param interval: time interval to be converted
        :return: time in UTC

        '''
        local = pytz.timezone("America/Los_Angeles")
        naive = datetime.datetime.strptime(interval, "%Y-%m-%d %H:%M:%S")
        local_dt = local.localize(naive, is_dst=None)
        utc_dt = local_dt.astimezone(pytz.utc)

        return utc_dt

    def calculate_effective_prefixes(self, start_interval=1451692800):
        '''
        This method calculates the number of effective /24
        prefixes that lie underneath a specified route prefix
        :param start_interval: the start interval of the data
        stream
        :return: number of effective prefixes under the route's
        root prefix
        '''

        stream = BGPStream()
        rec = BGPRecord()

        stream.add_filter('collector', self.collector_name)
        stream.add_filter('record-type', 'ribs')

        if isinstance(start_interval, datetime.datetime):
            interval_start_utc = self.convert_interval_to_utc(start_interval)
            stream.add_interval_filter(interval_start_utc - 300, interval_start_utc + 300)
        else:
            stream.add_interval_filter(start_interval - 300, start_interval + 300)

        stream.start()
        print "Starting routing table parsing"
        while (stream.get_next_record(rec)):
            elem = rec.get_next_elem()
            while elem:
                # Get the peer ASN and IP. We then construct a peer_id, since a collector
                # can establish multiple connections with the same ASN.
                peer_asn = elem.peer_asn
                peer_asn_ip = elem.peer_address

                # make this an unmodifiable tuple
                peer_id = (peer_asn, peer_asn_ip)
                peer_route_trie = self.peer_trie_handles[peer_id]

                # Do a single level search of the route prefix to
                # find the left and right prefix advertisements
                single_level_prefixes = \
                    peer_route_trie.single_level_search(elem.fields['prefix'])
                print single_level_prefixes

                for prefix in single_level_prefixes:
                    trie_node = peer_route_trie.search_exact(str(prefix))
                    as_path = trie_node.data['as-path'].split(" ")
                    as_path_headless = as_path[1:-1]
                    print "AS-Path : ", as_path
                    as_headless_len = len(as_path_headless)
                    if as_headless_len > 1:
                        for i in range(0, as_headless_len-1):
                            print as_path_headless[i], as_path_headless[i+1]
                            if as_path_headless[i] in self.aslink_datastore:
                                self.aslink_datastore[as_path_headless[i]] += 1
                            else:
                                self.aslink_datastore[as_path_headless[i]] = 1

                prefix_count = len(single_level_prefixes)
                root_24_prefix_count = 0
                lr_24_prefix_count1 = lr_24_prefix_count2 = 0

                # The /24 prefixes below the advertised prefix are calculated
                # as all the /24 prefixes served by the root - sum of the /24
                # prefixes served by root's children
                if (prefix_count == 1):
                    root_24_prefix_count = \
                        2 ** (24 - int(str(single_level_prefixes[0]).lstrip('<')
                                       .rstrip('>').split('/')[1]))
                elif (prefix_count == 2):
                    root_24_prefix_count = \
                        2 ** (24 - int(str(single_level_prefixes[0]).lstrip('<')
                                       .rstrip('>').split('/')[1]))
                    lr_24_prefix_count1 = \
                        2 ** (24 - int(str(single_level_prefixes[1]).lstrip('<')
                                        .rstrip('>').split('/')[1]))
                else:
                    root_24_prefix_count = \
                        2 ** (24 - int(str(single_level_prefixes[0]).lstrip('<')
                                       .rstrip('>').split('/')[1]))
                    lr_24_prefix_count1 = \
                        2 ** (24 - int(str(single_level_prefixes[1]).lstrip('<')
                                       .rstrip('>').split('/')[1]))
                    lr_24_prefix_count2 = \
                        2 ** (24 - int(str(single_level_prefixes[2]).lstrip('<')
                                       .rstrip('>').split('/')[1]))

                effective_24_prefix_count = \
                    root_24_prefix_count - (lr_24_prefix_count1 +
                                            lr_24_prefix_count2)

                print elem.fields['as-path'], effective_24_prefix_count
                elem = rec.get_next_elem()


if __name__ == "__main__":

    collector_stream = BGPCollectorStream()
    collector_stream.create_trie_from_bgpstream_info()
    collector_stream.calculate_effective_prefixes()

    # # Create a new tree
    # rtree = radix.Radix()
    #
    # # Adding a node returns a RadixNode object. You can create
    # # arbitrary members in its 'data' dict to store your data
    # test_prefix = RadixPrefix("10.10.10.1/24")
    # print test_prefix.network
    # print test_prefix.bitlen
    #
    # rnode = rtree.add("10.0.0.1/23")
    # rnode.data["blah"] = "whatever you want"
    #
    # rnode = rtree.add("10.0.0.1/24")
    # rnode.data["bla"] = "whatever you want"
    #
    # rnode = rtree.add("10.0.0.1/25")
    # rnode.data["bl"] = "whatever you want"
    #
    # rnodes = rtree.single_level_search("10.0.0.1/23")
    # for node in rnodes:
    #     print node.prefix
