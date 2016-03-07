#!/usr/bin/env python
import json

stream_start = 1454284800
stream_end = 1454285700

prefixData = {}

def create_time_buckets(start, end):
    time_step = 300 #5 multiprocessing
    buckets = []
    for x in xrange(start, end, time_step):
        new_end = x + 300
        window = {"start": x, "end": new_end, "count": 0}
        buckets.append(window)
    return buckets



def deal_with_time_bucket_junk(prefix, timestamp):
    currPrefixData = prefixData.get(prefix)
    if not currPrefixData:
                currPrefixData = buckets
    duration = timestamp - stream_start
    bucket = int(duration / 300)
    #pick correct bucket -> then
    currPrefixData[bucket]["count"] += 1
    prefixData[prefix] = currPrefixData


buckets =  create_time_buckets(1454284800, 1454285700)

deal_with_time_bucket_junk("192.168.1.1/24",1454284850)
deal_with_time_bucket_junk("192.168.1.1/24",1454285650)


print json.dumps(prefixData, indent=4)
