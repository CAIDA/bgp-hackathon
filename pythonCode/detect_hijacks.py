# -*- coding: utf-8 -*-
import os
import json
import logging

from functools import partial
from datetime import datetime
from collections import defaultdict

from caida_filter import caida_filter_annaunce, is_legittimate


from tabi.core import InternalMessage
from tabi.helpers import get_as_origin
from tabi.rib import EmulatedRIB, Radix
from tabi.emulator import detect_conflicts
from tabi.annotate import annotate_if_relation, annotate_if_route_objects, \
    annotate_if_roa, annotate_if_direct, annotate_with_type, \
    fill_relation_struct, fill_ro_struct, fill_roa_struct

from kafka import KafkaClient
from kafka.consumer import KafkaConsumer
from kafka.protocol import create_message
from kafka.common import ProduceRequest

from prometheus_client import Counter, Gauge, start_http_server


validated = Counter('validated', 'RPKI or route objects validated', ["collector"])
relation = Counter('relation', 'aut-num org or mnt relation', ["collector"])
connected = Counter('connected', 'same path', ["collector"])
caida_relation = Counter('caida_relation', 'somehow related', ["collector"])
caida_private = Counter('caida_private', 'somehow related', ["collector"])
caida_as2org = Counter('caida_as2org', 'somehow related', ["collector"])
caida_cone = Counter('caida_cone', 'somehow related', ["collector"])
caida_as2rel = Counter('caida_as2rel', 'somehow related', ["collector"])
abnormal = Counter('abnormal', 'no classification', ["collector"])

events_latency = Gauge("events_latency", "BGP event detection latency", ["collector", "peer_as"])
all_events = Counter("all_events", "BGP conflicts events", ["collector", "filtered"])

logger = logging.getLogger()


PARTITIONS = {
    "rrc18": 0,
    "rrc19": 1,
    "rrc20": 2,
    "rrc21": 3,
    "caida-bmp": 4,
}


def kafka_format(collector, message):
    data = json.loads(message)
    as_path = data.get("as_path", None)
    if as_path is not None:
        origins = frozenset(get_as_origin(as_path))
        yield InternalMessage(data.get("type", "U"),
                              data["timestamp"],
                              collector,
                              int(data["peer_as"]),
                              data["peer_ip"],
                              data["prefix"],
                              origins,
                              as_path)
    else:
        yield InternalMessage("W",
                              data["timestamp"],
                              collector,
                              int(data["peer_as"]),
                              data["peer_ip"],
                              data["prefix"],
                              None,
                              None)


class KafkaInputBview(object):
    """
    Emulates a bview from messages stored in a kafka topic.
    """

    def __init__(self, consumer, collector):
        self.consumer = consumer
        self.collector = collector

    def open(self):
        return self

    def close(self):
        pass

    def __iter__(self):
        tmp_rib = EmulatedRIB()

        # go to the tail of the log, we should get all prefixes from there
        self.consumer.set_topic_partitions(("rib-{}".format(self.collector), 0, 0))

        logger.info("consuming from the start to build bview")
        for data in kafka_iter(self.consumer):
            # kafka internal message used to represent that a key was deleted
            if data is None:
                continue
            message = json.loads(data)
            node = tmp_rib.radix.add(message["prefix"])
            key = message["peer_as"]
            c = node.data.get(key, 0)
            # end of the bview if we already have this prefix in our RIB
            if c != 0:
                logger.info("end of bview")
                break
            node.data[key] = c + 1
            # fake bview
            message["type"] = "F"
            yield json.dumps(message)
        del tmp_rib

    def __enter__(self):
        return iter(self)

    def __exit__(self, exc_type, exc, traceback):
        pass


def kafka_iter(consumer):
    """
    Iterate over messages from the kafka topic.
    """
    for data in consumer:
        if data.value is not None:
            yield data.value


def kafka_input(collector, **options):
    group_id = options.pop("group_id", "hackathon")
    broker = options.pop("broker", os.getenv("KAFKA_BROKER", "").split(","))

    consumer = KafkaConsumer(collector, metadata_broker_list=broker,
                             group_id=group_id, auto_commit_enable=False)
    return {
        "collector": collector,
        "files": [KafkaInputBview(consumer, collector), kafka_iter(consumer)],
        "format": kafka_format
    }


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("collector")
    parser.add_argument("--from-timestamp", type=float)
    parser.add_argument("--our-servers", default=",".join(["comet-17-11.sdsc.edu:9092", "comet-17-22.sdsc.edu:9092", "comet-17-26.sdsc.edu:9092"]))
    parser.add_argument("--irr-ro-file",
                        help="CSV file containing IRR route objects")
    parser.add_argument("--irr-mnt-file",
                        help="CSV file containing IRR maintainer objects")
    parser.add_argument("--irr-org-file",
                        help="CSV file containing IRR organisation objects")
    parser.add_argument("--rpki-roa-file",
                        help="CSV file containing ROA")
    parser.add_argument("--as-rel-file",
                        help="TXT file containing AS relation")
    parser.add_argument("--ppdc-ases-file")
    parser.add_argument("--as2org-file",
                        help="TXT file containing AS to organizations")

    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)

    kwargs = kafka_input(args.collector, broker=args.our_servers.split(","))

    logger.info("loading metadata...")
    funcs = [annotate_if_direct]
    if args.irr_ro_file is not None:
        ro_rad_tree = Radix()
        fill_ro_struct(args.irr_ro_file, ro_rad_tree)
        funcs.append(partial(annotate_if_route_objects, ro_rad_tree))

    if args.rpki_roa_file is not None:
        roa_rad_tree = Radix()
        fill_roa_struct(args.rpki_roa_file, roa_rad_tree)
        funcs.append(partial(annotate_if_roa, ro_rad_tree))

    if args.irr_org_file is not None and args.irr_mnt_file:
        relations_dict = dict()
        fill_relation_struct(args.irr_org_file, relations_dict,
                             "organisations")
        fill_relation_struct(args.irr_mnt_file, relations_dict, "maintainers")
        funcs.append(partial(annotate_if_relation, relations_dict))

    if args.as_rel_file is not None and args.ppdc_ases_file is not None and args.as2org_file is not None:
        a, b,c,d = caida_filter_annaunce(args.as_rel_file, args.ppdc_ases_file, args.as2org_file)
        funcs.append(partial(is_legittimate, a, b, c,d))

    if args.from_timestamp is None:
        consumer = KafkaConsumer("conflicts",
                                 metadata_broker_list=args.our_servers.split(","),
                                 group_id="detector",
                                 auto_commit_enable=False)
        offset, = consumer.get_partition_offsets("conflicts", PARTITIONS[args.collector], -1, 1)
        consumer.set_topic_partitions({("conflicts", PARTITIONS[args.collector]): offset - 1})
        last_message = next(iter(consumer))
        last_data = json.loads(last_message.value)
        last_ts = last_data["timestamp"]
        logger.info("last detected event was at offset %s timestamp %s", offset, last_ts)
    else:
        last_ts = args.from_timestamp

    logger.info("detecting conflicts newer than %s", datetime.utcfromtimestamp(last_ts))

    start_http_server(4240 + PARTITIONS[args.collector])

    client = KafkaClient(args.our_servers.split(","))
    stats = defaultdict(int)
    for msg in detect_conflicts(**kwargs):
        ts = msg.get("timestamp", 0)
        if last_ts is not None and ts <= last_ts:
            continue

        events_latency.labels(args.collector, str(msg["peer_as"])).set((datetime.utcnow() - datetime.utcfromtimestamp(ts)).seconds)

        for enrich_func in funcs:
            enrich_func(msg)

        filter_out = False
        # skip these events that are probably legitimate
        if "valid" in msg:
            validated.labels(args.collector).inc()
            filter_out = True
        if "relation" in msg:
            relation.labels(args.collector).inc()
            filter_out = True
        if "direct" in msg:
            connected.labels(args.collector).inc()
            filter_out = True
        if msg.get("caida_private", False) is True:
            caida_private.labels(args.collector).inc()
            filter_out = True
        if msg.get("caida_as2org", False) is True:
            caida_as2org.labels(args.collector).inc()
            filter_out = True
        if msg.get("caida_relation", False) is True:
            caida_relation.labels(args.collector).inc()
            filter_out = True
        if msg.get("caida_cone", False) is True:
            caida_cone.labels(args.collector).inc()
            filter_out = True
        if msg.get("caida_as2rel", False) is True:
            caida_as2rel.labels(args.collector).inc()
            filter_out = True

        all_events.labels(args.collector, filter_out).inc()

        if filter_out:
            continue

        abnormal.labels(args.collector).inc()

        client.send_produce_request([ProduceRequest("conflicts", PARTITIONS[args.collector], [create_message(json.dumps(msg))])])

