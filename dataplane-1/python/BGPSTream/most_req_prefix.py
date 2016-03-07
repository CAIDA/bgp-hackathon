from _pybgpstream import BGPStream, BGPRecord, BGPElem
from collections import defaultdict
from optparse import OptionParser


def getopts():
    parser = OptionParser()
    parser.add_option('-l', dest='limit', type=int,
                      default=0, help='only display prefixes with more than N updates')
    parser.add_option('-s', dest='start_time', type=int,
                      default=1454284800, help='start time')
    parser.add_option('-e', dest='end_time', type=int,
                      default=1454288400, help='end time')

    return parser.parse_args()


def main():
    (options, args) = getopts()
    limit = options.limit
    start = options.start_time
    end = options.end_time

    # Create a new bgpstream instance and a reusable bgprecord instance
    stream = BGPStream()
    rec = BGPRecord()

    # Consider RIPE RRC 10 only
    stream.add_filter('record-type', 'updates')
    stream.add_filter('collector', 'rrc00')
    stream.add_filter('prefix', '0.0.0.0/0')

    # Consider this time interval:
    # Sat Aug  1 08:20:11 UTC 2015
    # stream.add_interval_filter(1438417216,1438417216)
    # stream.add_interval_filter(1451606400,1454785264)
    #stream.add_interval_filter(1454630400, 1454716800)
    # 1 hour
    #1454284800 - 1454288400

    stream.add_interval_filter(start, end)

    # Start the stream
    stream.start()

    # Get next record
    prefixes_update = defaultdict(int)
    prefixes_withdraw = defaultdict(int)

    while stream.get_next_record(rec):
        # Print the record information only if it is not a valid record
        if rec.status != "valid":
            pass
            # print '*', rec.project, rec.collector, rec.type, rec.time, rec.status
        else:
            elem = rec.get_next_elem()
            while elem:
                if elem.type == 'A':
                    #print elem.fields['as-path']
                    prefixes_update[elem.fields['prefix']] += 1

                if elem.type == 'W':
                    prefixes_withdraw[elem.fields['prefix']] += 1

                #print rec.project, rec.collector, rec.type, rec.time, rec.status,
                #print elem.type, elem.peer_address, elem.peer_asn, elem.fields
                elem = rec.get_next_elem()

    for k in prefixes_update:
        if prefixes_update[k] >= limit:
            print k + "\t" + str(prefixes_update[k]) + "\t" + str(prefixes_withdraw[k])

if __name__ == '__main__':
    main()