import argparse
import json
from sets import Set

parser = argparse.ArgumentParser("Computes the best collectors for each pair src/dst.")
parser.add_argument("infile", type=str, help="Infile")
parser.add_argument("outfile", type=str, help="Outfile")

args = parser.parse_args()
infile = args.infile
outfile = args.outfile

threshold = 0.50
res_dic = {}


with open(infile) as fd_in:    
    data = json.load(fd_in)

i = 0

for dst_pref in data:
    i += 1
    print i
    if i == 200:
        break
    for peer_info in data[dst_pref]:
        peer_ip = peer_info.split(':')[1]

        for src_ip in data[dst_pref][peer_info]:
            tab = data[dst_pref][peer_info][src_ip]
            #print dst_pref+'\t'+peer_ip+'\t'+src_ip+'\t'+str(tab)

            tmp_peer_set = Set()
            score = float(tab[0])/float(tab[1])


            if src_ip not in res_dic:
                res_dic[src_ip] = {}
            if dst_pref not in res_dic[src_ip]:
                res_dic[src_ip][dst_pref] = Set()

            if score < threshold:
                res_dic[src_ip][dst_pref].add(peer_info)

fd_out = open(outfile, 'w')
for src in res_dic:
    for dst in res_dic[src]:
        fd_out.write(str(src)+'\t'+str(dst)+'\t')
        peer_str = ''
        for p in res_dic[src][dst]:
            #cname = p.split(':')[0]
            #peer_ip = p.split(':')[1]

            peer_str += str(p)+','
        fd_out.write(peer_str[:-1]+'\n')
fd_out.close()
