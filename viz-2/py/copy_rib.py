import MySQLdb
from mysql_writer import MysqlWriter
import sys

# Create writer instance and start it in separate thread
writer = MysqlWriter()
writer.start()

openbmp_db = MySQLdb.connect("dyn55.caida.org", "openbmp", "openbmp", "openBMP")
openbmp_cursor = openbmp_db.cursor()

openbmp_cursor.execute('SELECT DISTINCT hash_id from bgp_peers')
peer_hash_ids = map(lambda x: x[0], openbmp_cursor.fetchall())
peer_hash_ids = peer_hash_ids[20:]
print(peer_hash_ids)

sql = '''
  SELECT
    p.peer_addr as router,
    prefix as prefix_addr,
    prefix_len,
    floor(unix_timestamp(rib.timestamp)) as timestamp,
    a.as_Path as as_path,
    a.community_list communities
  FROM rib
    JOIN path_attrs a
      ON (rib.path_attr_hash_id = a.hash_id)
    JOIN bgp_peers p
      ON (rib.peer_hash_id = p.hash_id)
  WHERE rib.peer_hash_id = '%s'
    AND isWithdrawn = False
'''
sql = sql.replace('\n', ' ')

# Fetch DB for all peers
for peer_hash_id in peer_hash_ids:
  print('Copying RIB for peer_hash_id %s' % peer_hash_id)
  sql_st = sql % peer_hash_id
  openbmp_cursor.execute(sql_st)
  rows = openbmp_cursor.fetchall()
  for row in rows:
    if len(row) < 6:
      print('Skipping malformed row: ')
      print(row)
      continue

    as_path = None
    try:
      as_path = row[4].replace('{', '').replace('}', '')
      as_path = filter(lambda x: x.strip() != '', as_path.strip().split(' '))
      as_path = map(lambda x: int(x.strip()), as_path)
    except:
      as_path = []
      print('failed to decode as_path: %s' % str(row[4]))

    origin_asn = 0
    if len(as_path) > 0:
      origin_asn = as_path[-1]

    record = {
      'router': row[0],
      'prefix': '%s/%d' % (row[1], row[2]),
      'timestamp': row[3],
      'type': 'A',
      'origin_asn': origin_asn,
      'as_path': as_path,
      'communities': row[5]}
    writer.add(record)
  print('Retrieved %d records for the peer' % len(rows))

# Close DB
openbmp_db.close()
