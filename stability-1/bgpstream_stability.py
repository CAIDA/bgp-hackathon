#!/usr/bin/env python
#
# Copyright (C) 2015
# Authors: Nathan Owens & Andrew Mulhern
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.
#


import sys
import json
import copy
import math
import urllib
import multiprocessing
from _pybgpstream import BGPStream, BGPRecord, BGPElem
from collections import defaultdict
from datetime import datetime


def deal_with_time_bucket_junk(prefix, timestamp):

    if prefix not in raw_bgp_stream_data:
        newBuckets = copy.deepcopy(buckets)
        raw_bgp_stream_data[prefix] = newBuckets

    duration = timestamp - stream_start
    bucket = int(duration / 300)
    try:
        raw_bgp_stream_data[prefix][bucket]["count"] += 1
    except:
        pass


def create_time_buckets(start, end):
    time_step = 300  # 5 multiprocessing
    buckets = []
    for x in xrange(start, end, time_step):
        new_end = x + 300
        window = {"start": x, "end": new_end, "count": 0}
        buckets.append(window)
    return buckets


def get_ripe_probes(prefix_list):

    def get_probe_list(ip_proto, prefix_data, return_dict):

        prefix = prefix_data[0]
        count = prefix_data[1]
        bucket_data = prefix_data[2]

        url = "https://atlas.ripe.net/api/v1/probe/?format=json&prefix_%s=%s" % (ip_proto, prefix)
        probe_data = json.loads(urllib.urlopen(url).read())

        probe_count = probe_data["meta"]["total_count"]

        probe_ids = []
        if probe_count > 0:
            for probe in probe_data["objects"]:
                probe_id = probe["id"]
                probe_ids.append(probe_id)

	if len(probe_ids) > 0:
		return_dict[prefix] = {"count": count, "bucket_data": bucket_data, "probe_count": probe_count, "probe_ids": probe_ids}
	return

    jobs = []
    manager = multiprocessing.Manager()
    return_dict = manager.dict()

    for prefix_data in prefix_list:
        prefix = prefix_data[0]

        if "." in prefix:
            job = multiprocessing.Process(target=get_probe_list, args=("v4", prefix_data, return_dict))

        elif ":" in prefix:
            job = multiprocessing.Process(target=get_probe_list, args=("v6", prefix_data, return_dict))

        jobs.append(job)
        job.start()

    for job in jobs:
        job.join()

    return dict(return_dict)


if __name__ == "__main__":

    try:
        stream_start = int(sys.argv[1])
        stream_end = int(sys.argv[2])
        out_file_name = sys.argv[3]

    except:
        print "Usage: %s [start time] [end time] [output file name]" %(sys.argv[0])
        exit()

    #stream_start = 1454284800
    #stream_end = 1454288400
    buckets = create_time_buckets(stream_start, stream_end)
    
    prefixList = []
    raw_bgp_stream_data = {}
    
    stream = BGPStream()
    rec = BGPRecord()
    stream.add_filter('collector', 'rrc06')
    stream.add_filter('record-type', 'updates')
    stream.add_interval_filter(stream_start, stream_end)
    stream.start()
    
    while(stream.get_next_record(rec)):
    
        elem = rec.get_next_elem()
    
        while(elem):
    
            prefix = elem.fields.get("prefix", "")
            time_stamp = rec.time  # unix epoc timestamp 1427846670
    
            if prefix != "":
    		deal_with_time_bucket_junk(prefix, time_stamp)
    
            elem = rec.get_next_elem()
    
    
    for prefix in list(raw_bgp_stream_data):
        for bucket in list(raw_bgp_stream_data[prefix]):
            if bucket["count"] < 3:
                raw_bgp_stream_data[prefix].remove(bucket)
    
    
    for prefix in raw_bgp_stream_data:
    
        index = 0
        max_index = 0
        max_val = 0
        last_val = 0
    
        for bucket in raw_bgp_stream_data[prefix]:
    
            curr = bucket["count"]
            if curr > last_val:
                max_val = curr
    
            index += 1
            last_val = curr
    
        if raw_bgp_stream_data[prefix]:
            prefixList.append((prefix, max_val, raw_bgp_stream_data[prefix][max_index]))
    
    
    prefixListWithProbes = get_ripe_probes(prefixList)
    
    
    import get_probe_data
    results = []
    
    for prefix, values in prefixListWithProbes.iteritems():
        start_time = values["bucket_data"]["start"]
        end_time = values["bucket_data"]["end"]
        count = values["count"]
    
        probe_list = values["probe_ids"]
        for probe in probe_list:
            packet_loss = get_probe_data.get_packet_loss(probe, start_time, end_time)

    	results.append({"prefix":prefix, "count":count, "start_time":start_time, "end_time":end_time, "probe":probe, "packet_loss":packet_loss})
    
    sorted_results = list(sorted(results, reverse=True, key = lambda x: (x["count"], x["packet_loss"])))
    out_file = open(out_file_name, "w")
    out_file.write(json.dumps(sorted_results, indent=3))
    out_file.close()
