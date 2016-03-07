#!/usr/bin/env python

import json

bubble_format = """{
   "name":"stability-1",
   "children":[
      {
         "name":"packet_loss",
         "children":[
         ]
      },
      {
         "name":"no_packet_loss",
         "children":[
         ]
      }
   ]
}"""
bubble_data = json.loads(bubble_format)

prefix_data = json.loads(open("data_6h.json", "ro").read())

for prefix in prefix_data:

	if not prefix["packet_loss"]:
		bubble_data["children"][0]["children"].append({"name": prefix["prefix"], "size": prefix["count"]})
	else:
		bubble_data["children"][1]["children"].append({"name": prefix["prefix"], "size": prefix["count"]})

outfile = open("bubble_data.json", "w")
outfile.write(json.dumps(bubble_data, indent=4))
outfile.close()
