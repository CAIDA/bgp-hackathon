from _pybgpstream import BGPStream, BGPRecord, BGPElem

# Create a new bgpstream instance and a reusable bgprecord instance
stream = BGPStream()
rec = BGPRecord()

start = 1454800000
end = 1454802000
target_pref = '200.7.6.0/24'

print start, end, target_pref
print target_pref

stream.add_filter('prefix', target_pref)

# Consider RIPE RRC 10 only
# stream.add_filter('record-type', 'updates')
stream.add_filter('collector', 'rrc00')
stream.add_interval_filter(start, end)

# Consider this time interval:
# Sat Aug  1 08:20:11 UTC 2015
# """ Very short period for test """
# stream.add_interval_filter(start, end)
# """ Jan till now """
#     stream.add_interval_filter(1451606400,1454785264)
# """ yesterday """
#     stream.add_interval_filter(1454630400, 1454716800)

# Start the stream
stream.start()

# Get next record
cnt = 0
while stream.get_next_record(rec):
    # Print the record information only if it is not a valid record
    if rec.status == 'valid':
        cnt += 1
        elem = rec.get_next_elem()
        while elem:
            if elem.type == 'S':
                continue
            # Print record and elem information
            print rec.project, rec.collector, rec.type, rec.time, rec.status,
            print elem.type, elem.peer_address, elem.peer_asn, elem.fields
#                 bw.write('{0}\t{1}\t{2}\t{3}\t{4}\t{5}\t{6}\t{7}\t{8}\t{9}\n'.format(
#                         rec.project, rec.collector, rec.type, rec.time, rec.status,
#                         elem.type, elem.fields['prefix'], elem.peer_address, elem.peer_asn, elem.fields))
            elem = rec.get_next_elem()
