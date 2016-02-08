#!/usr/bin/env python
from datetime import datetime
from ripe.atlas.cousteau import AtlasResultsRequest
from ripe.atlas.sagan import PingResult

def get_packet_loss(probe, start_time, end_time):

	kwargs = {
		"msm_id": "1001", ## K Root Servers
		"start": start_time - 300,
		"stop": end_time + 300,
		"probe_ids": [probe]
	}

	is_success, results = AtlasResultsRequest(**kwargs).create()

	count = 0
	if is_success:
		for result in results:
			ping_data = PingResult(result)
			if ping_data.packets_sent != ping_data.packets_received:
				count += 1
	packet_loss = False
	if count > 0:
		packet_loss = True

	return packet_loss

