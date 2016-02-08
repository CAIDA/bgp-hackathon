# -*- coding: utf-8 -*-

import json
import logging

from kafka.consumer import KafkaConsumer
from tabi.rib import Radix

logger = logging.getLogger(__name__)


COLLECTORS=["rrc18", "rrc19", "rrc20", "rrc21", "caida-bmp"]


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="get a feed ofannounces from a BGP collector")
    parser.add_argument("collector", nargs="*")
    parser.add_argument("--offset", type=int)
    parser.add_argument("--prefixes-file")
    parser.add_argument("--our-servers", default=",".join(["comet-17-11.sdsc.edu:9092", "comet-17-22.sdsc.edu:9092", "comet-17-26.sdsc.edu:9092"]))

    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)

    if args.collector is not None:
        topics = ["rib-{}".format(c) for c in args.collector]
    else:
        topics = ["rib-{}".format(c) for c in COLLECTORS]

    consumer = KafkaConsumer(*topics,
                             bootstrap_servers=args.our_servers.split(","),
                             group_id="follower")

    if args.offset is not None:
        consumer.set_topic_partitions({(t, 0): args.offset for t in topics})

    # setup filters
    filters = []

    if args.prefixes_file is not None:
        filter_prefixes = Radix()
        with open(args.prefixes_file, "r") as f:
            for prefix in f:
                filter_prefixes.add(prefix.strip())

        def func(data):
            return len(list(filter_prefixes.search_covering(data["prefix"]))) > 0
        logger.info("filtering on prefixes from the file %s", args.prefixes_file)
        filters.append(func)

    for item in consumer:
        if item.value is None:
            continue
        data = json.loads(item.value)
        if len(filters) == 0 or any(f(data) for f in filters):
            print(data)
