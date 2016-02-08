from optparse import OptionParser
from _pybgpstream import BGPStream, BGPRecord, BGPElem
from sets import Set
from rib import Rib


def getopts():
    parser = OptionParser()
    parser.add_option('-i', dest='in_folder', type=str,
                      default='', help='use raw counts')
    parser.add_option('-o', dest='updates_file', type=str,
                      default="updates.txt", help='use raw counts')
    parser.add_option('-r', dest='rib_file', type=str,
                      default="rib.txt", help='use raw counts')
    parser.add_option('-s', dest='start_time', type=int,
                      default=1454630400, help='start time')
    parser.add_option('-e', dest='end_time', type=int,
                      default=1454716800, help='end time')

    # parser.add_option('--file', dest='fileName', type=str,
    #   default="profiles_10k.txt", help='use expected counts')
    return parser.parse_args()


def main(rib, target_prefs):

        
    # Create a new bgpstream instance and a reusable bgprecord instance
    stream = BGPStream()
    rec = BGPRecord()

    with open('./data/stream_{0}'.format(start), 'wb') as bw:

        for ptmp in target_prefs:
            stream.add_filter('prefix', ptmp)

        # Consider RIPE RRC 10 only
        stream.add_filter('record-type', 'updates')
        stream.add_filter('record-type', 'ribs')
        #stream.add_filter('collector', 'rrc04')
        stream.add_filter('project', 'ris')
        stream.add_filter('project', 'routeviews')

        stream.add_interval_filter(start-60*60*8, start)
        stream.add_rib_period_filter(10000000000000)        

        # Start the stream
        stream.start()

        while stream.get_next_record(rec):
            # Print the record information only if it is not a valid record
            if rec.status != "valid":
                continue

            #if rec.time < start:
            elem = rec.get_next_elem()
            while elem:

                if elem.type == 'A' or elem.type == 'R':
                    rib.add_to_rib(rec.collector, elem.peer_address, elem.fields['prefix'], elem.time, elem.fields['as-path'])

                elem = rec.get_next_elem()

            #else:

        rib.flush()

    print 'Successful termination; Start time: {0}'.format(start)

if __name__ == '__main__':

    (options, args) = getopts()
    start = options.start_time
    end = options.end_time

    target_prefs = Set()
    with open('./../../atlas/anchor_prefix.txt', 'rb') as br:
        for l in br:
            target_prefs.add(l.strip())


    fd_up = open('./data/stream_{0}'.format(start), 'w', 100)
    fd_rib = open('./data/rib', 'w', 100)
    rib = Rib(fd_rib, fd_up)    

    main(rib, target_prefs)

    fd_up.close()
    fd_rib.close()
