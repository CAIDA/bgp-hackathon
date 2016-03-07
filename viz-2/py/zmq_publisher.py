import zmq
import sys
import json

class ZmqPublisher:
  def __init__(self, port):
    self.context = zmq.Context()
    self.socket = self.context.socket(zmq.PUB)
    url = "tcp://*:%d" % port
    self.socket.bind(url)
    print('Started publisher on %s' % url)

  # Data is assummed to be map which has 'prefix' and 'router' attributes atleast
  def publish(self, data):
    data_str = json.dumps(data)
    self.socket.send_string('p-%s' % data['prefix'], zmq.SNDMORE)
    self.socket.send_string(data_str)
    self.socket.send_string('r-%s' % data['router'], zmq.SNDMORE)
    self.socket.send_string(data_str)

'''
publisher = ZmqPublisher(12345)
a = None
while a != 'exit':
  a = input('Enter data to publish: ')
  publisher.publish(a)
'''
