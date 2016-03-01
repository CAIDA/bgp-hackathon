# -*- coding: utf-8 -*-

import json
import logging

from functools import partial

from kafka.consumer import KafkaConsumer

from tabi.rib import Radix
from tabi.helpers import get_as_origin

from caida_filter import caida_filter_annaunce

logger = logging.getLogger(__name__)


COLLECTORS = ["rrc18", "rrc19", "rrc20", "rrc21", "caida-bmp"]


def find_more_specific(consumer):
    rib = Radix()
    for item in consumer:
        data = json.loads(item.value)
        if "as_path" not in data:
            continue
        for node in rib.search_covering(data["prefix"]):
            for peer, as_path in node.data.iteritems():
                if peer != data["peer_as"]:
                    yield (node.prefix, as_path, data["prefix"], data["as_path"])
        node = rib.add(data["prefix"])
        node.data[data["peer_as"]] = data["as_path"]


def same_path(as_path1, as_path2):
    try:
        # all the AS but the peer and the origin
        if any([asn in as_path2 for asn in as_path1[1:-1]]):
            return True
        return False
    except:
        return False


def verify_path(as_path):
    try:
        p1 = as_path[-2]
        p2 = as_path[-1]
    except:
        # beurk
        return False

    if(p1 in relations and p2 in relations[p1]): return True
    if(p2 in relations and p1 in relations[p2]): return True

    if(p1 in childs): #if p1 has a parent means that it is a child
        if(p2 in childs[p1]): return True

    if(p2 in childs):
        if(p1 in childs[p2]): return True


    if(p1>64511 and p1<65535 or p1>=4200000000 and p1<4294967295): return True
    if(p2>64511 and p2<65535 or p2>=4200000000 and p2<4294967295): return True

    return False


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="get a feed ofannounces from a BGP collector")
    parser.add_argument("collector", nargs="*")
    parser.add_argument("--offset", type=int)
    parser.add_argument("--anycast-file")
    parser.add_argument("--our-servers", default=",".join(["comet-17-22.sdsc.edu:9092"]))
    parser.add_argument("--as-rel-file",
                        help="TXT file containing AS relation")
    parser.add_argument("--ppdc-ases-file")

    args = parser.parse_args()

    collectors = COLLECTORS if len(args.collector) == 0 else args.collector

    logging.basicConfig(level=logging.INFO)

    topics = ["rib-{}".format(c) for c in collectors]
    logger.info("using topics %s", topics)

    consumer = KafkaConsumer(*topics,
                             bootstrap_servers=args.our_servers.split(","),
                             group_id="follower")

    if args.offset is not None:
        consumer.set_topic_partitions({(t, 0): args.offset for t in topics})

    # setup filters
    filters = []

    if args.anycast_file is not None:
        anycast = Radix()
        count = 0
        with open(args.anycast_file, "r") as f:
            for prefix in f:
                if not prefix.startswith("#"):
                    anycast.add(prefix.strip())
                    count += 1
        logger.info("loaded %s prefixes in the anycast list", count)
        logger.info("filtering on prefixes from the file %s", args.anycast_file)
    else:
        raise ValueError("please provide a anycast prefix list file")

    if args.as_rel_file is not None and args.ppdc_ases_file is not None:
        relations, childs, parents = caida_filter_annaunce(args.as_rel_file, args.ppdc_ases_file)
    else:
        raise ValueError("caida files required")
 
    for event in find_more_specific(consumer):

        try:
            as_path1 = event[1].split(" ")
            as_path2 = event[3].split(" ")
        except:
            logger.warning("oops %s", event)
            continue

        if len(as_path1) < 3 or len(as_path2) < 3:
            continue

        if same_path(as_path1, as_path2) or (verify_path(as_path1) and verify_path(as_path2)):
            continue

        nodes = list(anycast.search_covering(event[3]))
        print(event, "anycast" if len(nodes) > 0 else "unknown")
