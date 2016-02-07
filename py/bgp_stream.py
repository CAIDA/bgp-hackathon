from _pybgpstream import BGPStream, BGPRecord, BGPElem
import calendar
import time
import json
from publisher import ZmqPublisher
from dal import MySqlDAL
import threading
delay = 1800 # delay every message by 30min (to simulate RT)

def elem2bgplay(rec, elem):
    msg = {
        'router': elem.peer_address,
        'prefix': elem.fields['prefix'],
        'timestamp': elem.time,
    }
    if elem.type == 'A':
        try:
          as_path = map(lambda x: int(x), elem.fields['as-path'].split(' '))
        except:
          as_path = []
        msg['as_path'] = as_path
        msg['origin_asn'] =  as_path[-1] if len(as_path) > 0 else 0
        coms = elem.fields['communities']
        communities = " ".join(map(lambda c: '%s:%s' % (c['asn'], c['value']), coms))
        msg['communities'] = communities
    return msg

def generate_stream():
    bs = BGPStream()
    rec = BGPRecord()
    #initialize MySql
    a = MySqlDAL()
    a.start()

    #initialize the publisher in port number 12345
    publisher = ZmqPublisher(12345)

    bs.add_interval_filter(calendar.timegm(time.gmtime()) - delay, 0)
    # bs.add_filter('collector', 'route-views.sg')
    bs.add_filter('record-type', 'updates')
    bs.start()

    print('Beginning to read from stream')
    input_id = 0
    while bs.get_next_record(rec):
        elem = rec.get_next_elem()
        while elem is not None:
            # sleep until it is time to send this record
            '''
            now = calendar.timegm(time.gmtime())
            sim_time = now - delay
            if elem.time > sim_time:
                time.sleep(elem.time - sim_time)
            '''
            if elem.type not in ['A', 'W']:
                continue

            input_id += 1
            msg = elem2bgplay(rec, elem)
            msg['type'] = 'A'
            msg['id'] = input_id
            print(msg)

            # Publish the message
            publisher.publish(msg)

            # Write it to DB
            if elem.type == 'A':
                a.add(msg)
            elif elem.type == 'W':
                a.remove(msg)
            else:
                print "Error: Unknown type: " + elem.type
            elem = rec.get_next_elem()

generate_stream()

