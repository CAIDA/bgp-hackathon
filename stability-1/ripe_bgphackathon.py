from datetime import datetime
from ripe.atlas.cousteau import (
  Ping,
  Traceroute,
  AtlasSource,
  AtlasCreateRequest
)

def create_ripe_measurement(prefix_list):
    measurement_count = 0
    measurement_limit = 10
    ATLAS_API_KEY = "secret"
    for prefix, ip_list in prefix_list.iteritems():
        for ip in ip_list:

            ipAddr = ip
            count = 0
            descr = "Prefix: " + prefix + "Flapped " + str(count) + " times"

            ping = Ping(af=4, target=ipAddr, description=descr)

            traceroute = Traceroute(
                af=4,
                target=ipAddr,
                description=descr,
                protocol="ICMP",
            )

            source = AtlasSource(type="area", value="WW", requested=5)

            atlas_request = AtlasCreateRequest(
                start_time=datetime.utcnow(),
                key=ATLAS_API_KEY,
                measurements=[ping, traceroute],
                sources=[source],
                is_oneoff=True
            )

            (is_success, response) = atlas_request.create()
            measurement_count += 1
            if measurement_count > measurement_limit:
                break
