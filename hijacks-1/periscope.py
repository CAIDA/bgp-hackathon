import requests
import json
import random


api_url = "http://104.197.64.148/api"
# Get the available looking glass nodes
response = requests.get(api_url+"/host/list")
available_hosts = response.json()
print "Number of available hosts: "+str(len(available_hosts))
# Select 20 random looking glass hosts for the measurement
hosts = random.sample(available_hosts, 30)

# Construct the measurement array
measurement = dict()
measurement["argument"] = "212.58.246.104"
measurement["command"]= "bgp"
measurement["name"] = "test"
measurement["hosts"] = list()
for host in hosts:
    measurement["hosts"].append({"asn": host["asn"], "router": host["router"]})

print json.dumps(measurement)

# Send the data encoded as JSON string
response = requests.post(api_url+"/measurement", data=json.dumps(measurement))
# Convert the response from JSON string to array
decoded_response = response.json()
print decoded_response
print "Measurement ID is " + decoded_response["id"]
