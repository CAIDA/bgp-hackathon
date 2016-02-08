import MySQLdb
import Queue
import threading
import time
import json

class MysqlWriter(threading.Thread):
  def __init__(self):
    threading.Thread.__init__(self)
    self.connect()
    self.queue = Queue.Queue()
    self.limit = 5000

  def connect(self):
    self.db = MySQLdb.connect("127.0.0.1","has","mohib","koken")
    self.cursor = self.db.cursor()

  def add(self, route):
    self.queue.put((True, route))

  def remove(self, route):
    self.queue.put((False, route))

  def run(self):
    print('Starting MySQL writer thread')
    data = []
    routes = []
    last_action = True
    while True:
      reads = self.limit
      while not self.queue.empty() and reads > 0:
        reads -= 1
        action, route = self.queue.get()
        self.queue.task_done()
        if action == last_action:
          routes.append(route)
        else:
          data.append((last_action, routes))
          routes = [route]
          last_action = action
      data.append((last_action, routes))
      for action, routes in data:
        if len(routes) == 0:
          continue
        if action:
          self.add_routes(routes)
        else:
          self.remove_routes(routes)
      data = []
      routes = []
      if self.queue.empty():
        time.sleep(1)

  def add_routes(self, routes):
    rows = map(lambda r: (r['router'], r['prefix'], r['origin_asn'], json.dumps(r)), routes)
    sql = "REPLACE INTO bgp_routes(router,prefix,origin_asn,value) VALUES (%s,%s,%s,%s)"
    try:
      print('Adding %d entries to DB' % len(routes))
      self.cursor.executemany(sql, rows)
      self.db.commit()
    except Exception as e:
      print('Failed to add routes to db. %s' % str(e))

  def remove_routes(self, routes):
    print('Removing %d entries from DB' % len(routes))
    rows = map(lambda r: (r['router'], r['prefix']), routes)
    sql = "DELETE FROM bgp_routes WHERE router=%s and prefix=%s"
    try:
      self.cursor.executemany(sql, rows)
      self.db.commit()
    except Exception as e:
      print('Failed to remove routes from db. %s' % str(e))

#r1 = {'router':'r1', 'prefix':'adkfjoiaf', 'origin_asn': 1234, 'timestamp': 12145334643, 'communities': '123:124 3554:4654'}
#a = MysqlWriter()
#a.add(r1)

#a.run()
