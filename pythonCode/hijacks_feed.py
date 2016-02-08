# -*- coding: utf-8 -*-

import json
import logging

from kafka.consumer import KafkaConsumer
from tabi.rib import Radix

logger = logging.getLogger(__name__)


PARTITIONS = {
    "rrc18": 0,
    "rrc19": 1,
    "rrc20": 2,
    "rrc21": 3,
    "caida-bmp": 4,
}


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="get a feed of abnormal BGP conflicts")
    parser.add_argument("--offset", type=int)
    parser.add_argument("--prefixes-file")

    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO)

    consumer = KafkaConsumer("conflicts",
                             bootstrap_servers=["comet-17-22.sdsc.edu:9092", "comet-17-11.sdsc.edu:9092", "comet-17-26.sdsc.edu:9092"],
                             group_id="client")
    if args.offset is not None:
        topics = [("conflicts", i, args.offset) for i in PARTITIONS.values()]
        consumer.set_topic_partitions(*topics)

    # setup filters
    filters = []

    if args.prefixes_file is not None:
        filter_prefixes = Radix()
        with open(args.prefixes_file, "r") as f:
            for prefix in f:
                filter_prefixes.add(prefix.strip())

        def func(data):
            announce = data.get("announce")
            return announce is not None and announce["prefix"] in filter_prefixes
        logger.info("filtering on prefixes from the file %s", args.prefixes_file)
        filters.append(func)

    for item in consumer:
        data = json.loads(item.value)
        if len(filters) == 0 or any(f(data) for f in filters):
            print(data)
