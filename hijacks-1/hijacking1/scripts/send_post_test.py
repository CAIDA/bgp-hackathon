import requests
import json

# A flag that should always be set to True
is_alert = True

# A string you use to refer to yourself, the sender of the POST
data_source = 'myself'

# timestamp of the detected conflict
timestamp = 1454867393

# A pre-existing prefix, for which a conflict has been detected
prefix_old = '123.456.0.0/16'

# The AS number that was announcing prefix_old
AS_old = 100

# The prefix that conflicts with prefix_old
prefix_new = '123.456.0.0/16'

# The AS number that is making the conflicting announcement
AS_new = 150

# The path announced by AS_new
AS_path_new = [5, 6, 7, 123]

# The country code corresponding to AS_new
country_code = 'US'

# The information above, as well as any additional info can be put in a dictionary, then encoded as JSON
raw_data = {}
raw_data['is_alert'] = is_alert
raw_data['data_source'] = data_source
raw_data['timestamp'] = timestamp
raw_data['prefix_old'] = prefix_old
raw_data['AS_old'] = AS_old
raw_data['prefix_new'] = prefix_new
raw_data['AS_new'] = AS_new
raw_data['AS_path_new'] = AS_path_new
raw_data['country_code'] = country_code

raw_data_str = json.dumps(raw_data)
as_path_new_str = json.dumps(AS_path_new)

r = requests.post("http://132.249.65.97/alert-api/", data={'is_alert': is_alert, 'data_source': data_source, 'timestamp': timestamp, \
	                                                       'prefix_old': prefix_old, 'AS_old': AS_old, 'prefix_new': prefix_new, 'AS_new': AS_new, \
	                                                       'AS_path_new': as_path_new_str, 'country_code': country_code, 'raw_data': raw_data_str})
print(r)
print(r.text)
#print(r.url)
#print(r.json())