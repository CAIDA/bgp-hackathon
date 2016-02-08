#!/usr/bin/env python

import os
import json
import time
import logging

from datetime import datetime

from tabi.core import InternalMessage
from tabi.helpers import get_as_origin

from kafka import KafkaClient
from kafka.common import ProduceRequest
from kafka.protocol import create_message

from _pybgpstream import BGPStream, BGPRecord

from prometheus_client import Counter, Gauge, start_http_server

logger = logging.getLogger(__name__)


raw_bgp_messages = Counter("raw_bgp_messages", "all the BGP messages", ["collector", "peer_as"])
latency = Gauge("latency", "BGP peers latency", ["collector", "peer_as"])


def group_by_n(it, n):
    acc = []
    for elem in it:
        acc.append(elem)
        if len(acc) == n:
            yield acc
            del acc[:]
    yield acc


def bgpstream_format(collector, elem):
    raw_bgp_messages.labels(collector, str(elem.peer_asn)).inc()
    latency.labels(collector, str(elem.peer_asn)).set((datetime.utcnow() - datetime.utcfromtimestamp(elem.time)).seconds)
    if elem.type == "R" or elem.type == "A":
        as_path = elem.fields["as-path"]
        if len(as_path) > 0:
            origins = frozenset(get_as_origin(as_path))
            typ = "F" if elem.type == "R" else "U"
            yield InternalMessage(typ, float(elem.time), collector, int(elem.peer_asn),
                                  elem.peer_address, elem.fields["prefix"],
                                  origins, as_path)
    elif elem.type == "W":
        yield InternalMessage("W", float(elem.time), collector, int(elem.peer_asn),
                              elem.peer_address, elem.fields["prefix"],
                              None, None)


def messages_from_internal(it):
    for msg in it:
        ts = msg.timestamp
        key = "{}-{}".format(msg.prefix, msg.peer_as)
        if msg.as_path is None:
            yield create_message(json.dumps({"timestamp": ts,
                                             "prefix": msg.prefix,
                                             "peer_ip": msg.peer_ip,
                                             "peer_as": msg.peer_as}),
                                 key)
            yield create_message(None, key)
        else:
            yield create_message(json.dumps({"timestamp": ts,
                                             "prefix": msg.prefix,
                                             "as_path": msg.as_path,
                                             "peer_ip": msg.peer_ip,
                                             "peer_as": msg.peer_as}),
                                 key)


def iterate_stream(stream, collector):
    rec = BGPRecord()
    while stream.get_next_record(rec):
        elem = rec.get_next_elem()
        while elem:
            for item in bgpstream_format(collector, elem):
                yield item
            elem = rec.get_next_elem()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("collector")
    parser.add_argument("--our-servers", default="localhost:9092")

    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)

    save_file = "ts-{}".format(args.collector)

    stream = BGPStream()

    stream.add_filter('project', args.collector)

    if os.path.exists(save_file):
        with open(save_file, "r") as f:
            last_ts = int(float(f.read().strip()))
        logger.info("loading timestamp from file: %s", datetime.utcfromtimestamp(last_ts))
    else:
        # Consider RIBs dumps only
        now = time.time()
        last_ts = int(now - now % 3600)
        logger.info("loading from: %s", datetime.utcfromtimestamp(last_ts))

    stream.add_filter('record-type', 'ribs')
    stream.add_filter('record-type', 'updates')

    stream.add_interval_filter(last_ts, 0)

    # Start the stream
    stream.start()

    client = KafkaClient(args.our_servers.split(","))
    count = 0
    for batch in group_by_n(messages_from_internal(iterate_stream(stream, args.collector)), 1000):
        req = ProduceRequest("rib-{}".format(args.collector), 0, batch)
        for msg in reversed(req.messages):
            if msg.value is None:
                continue
            last_timestamp = json.loads(msg.value)["timestamp"]
            break

        count += len(batch)
        logger.info("sending %i", count)
        res = client.send_produce_request([req])
        try:
            # this is a bit buggy but it will do for now
            with open(save_file, "w") as f:
                f.write(str(last_timestamp))
        except:
            logger.warning("could not write offsets to %s", save_file)
            pass
