import time

alert1 = b'{"timestamp": 1454821580.2, "collector": "rrc21", "peer_as": 24482, "peer_ip": "37.49.236.228", "announce": {"type": "U", "prefix": "89.43.32.0/24", "asn": 58436, "as_path": "24482 50300 33182 1299 7473 56308 58436"}, "conflict_with": {"prefix": "89.43.32.0/21", "asn": 8708}, "asn": 8708, "type": "ABNORMAL"}'

alert2 = b'{"timestamp": 1454821580.2, "collector": "rrc21", "peer_as": 24482, "peer_ip": "37.49.236.228", "announce": {"type": "U", "prefix": "89.43.32.0/24", "asn": 58436, "as_path": "24482 50300 33182 1299 7473 56308 58436"}, "conflict_with": {"prefix": "184.164.230.0/23", "asn": 8708}, "asn": 8708, "type": "ABNORMAL"}'

while(True):
    for i in range(0,10):
        if i == 0:
            print(alert2)
        else:
            print(alert1)
        time.sleep(1)
