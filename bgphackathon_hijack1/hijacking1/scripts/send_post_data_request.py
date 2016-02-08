import requests

is_data_request = True
last_id_received = 0

r = requests.post("http://169.228.188.37/alert-api/", data={'is_data_request': is_data_request, 'last_id_received': last_id_received})
print(r)
print(r.text)
#print(r.url)
#print(r.json())