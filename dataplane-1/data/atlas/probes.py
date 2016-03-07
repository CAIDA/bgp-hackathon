import requests
import argparse
import json
from sets import Set
import time
import datetime


class Probe:

    def __init__ (self, probe_id, asn, country_code, lat, lgt, is_anchor, ipv4_prefix, ipv4='unknown', \
    nat="unknown", system="unknown", status="unknown", public="unknown", ipv6_works='no', \
    rfc1918 = 'unknown', tagged='unknown', home='unknown', core='unknown', isp='unknown', \
    academic='unknown', start_time='unknown'):
        self.probe_id = probe_id
        self.asn = asn
        self.lat = lat
        self.lgt = lgt
        self.country_code = country_code
        self.ipv4 = ipv4
        self.nat = nat
        self.system = system
        self.status = status
        self.public = public
        self.ipv6_works = ipv6_works
        self.rfc1918 = rfc1918
        self.tagged = tagged
        self.home = home
        self.core = core
        self.isp = isp
        self.academic = academic
        self.start_time = start_time
        self.is_anchor = is_anchor
        self.ipv4_prefix = ipv4_prefix

    def __hash__(self):    
        return hash(self.probe_id)

    def __repr__(self):
        return str(self.probe_id)+'\t'+str(self.asn)+'\t'+str(self.country_code)+'\t' \
            +str(self.is_anchor)+'\t'+str(self.ipv4_prefix)+'\t' \
            +str(self.lat)+'\t'+str(self.lgt)+'\t'+str(self.ipv4)+"\t"+self.nat+"\t" \
            +self.system+'\t'+str(self.status)+'\t'+str(self.public)+'\t'+str(self.ipv6_works)+'\t' \
            +str(self.rfc1918)+'\t'+str(self.tagged)+'\t'+str(self.home)+'\t' \
            +str(self.core)+'\t'+str(self.isp)+'\t'+str(self.academic)
    
    @staticmethod
    def header ():
        return '#ID\tASN\tCOUNTRY\tIS_ANCHOR\tV4_PREF\tLAT\tLGT\tIPV4\t\tNAT\tSYSTEM\t\tSTATUS\tPUBLIC\tIVP6\tRFC1918\tTAGGED\tHOME\tCORE\tISP\tACADEMIC'



def get_probes():
    r = requests.get('https://atlas.ripe.net/api/v1/probe-archive/')

    print r.status_code
    print r.headers

    probes_list = {}

    data = json.loads(r.text)

    for p in data["objects"]:
        nat = "unknown"
        system = "unknown"

        # Check if behind a NAT
        if "nat" in p["tags"]:
            nat = "nat"
        elif "no-nat" in p["tags"]:
            nat = "no-nat"

        # Check the system
        if "system-v1" in p["tags"]:
            system = "system-v1"
        elif "system-v2" in p["tags"]:
            system = "system-v2"
        elif "system-v3" in p["tags"]:
            system = "system-v3"
        elif "system-v4" in p["tags"]:
            system = "system-v4"

        # rfc1918
        if "system-ipv4-rfc1918" in p["tags"]:
            rfc1918 = True
        else:
            rfc1918 = False

        # Tagged by user
        tagged_by_users = False
        for t in p["tags"]:                
            if "system" not in t and t != 'nat' and t != 'no-nat':
                tagged_by_users = True
                break

        if tagged_by_users == False:
            fd = open('tmp', 'a+')
            fd.write(nat+' ')
            for i in p["tags"]:
                fd.write(str(i)+' ')

            fd.write('\n')
            fd.close()

        # Probe location
        home = False
        if "home" in p["tags"]:
            home = True
        core = False
        if "core" in p["tags"]:
            core = True
        isp = False
        if "isp" in p["tags"]:
            isp = True
        academic = False
        if "academic" in p["tags"]:
            academic = True
                

        ipv6_works = "no"
        if "system-ipv6-works" in p["tags"]:
            ipv6_works = "yes"

        if p["status"] == 1:
            probe = Probe(int(p["id"]), p['asn_v4'], \
            p['country_code'], p['latitude'], p['longitude'], p['is_anchor'], p['prefix_v4'],\
            p['address_v4'], nat, system, p["status"], p['is_public'], ipv6_works, \
            rfc1918, tagged_by_users, home, core, isp, academic)
            probes_list[int(p["id"])] = probe

    return probes_list


if __name__ == '__main__':

    parser = argparse.ArgumentParser("Print in an file all the IP addresses of the anchors.")
    parser.add_argument("outfile", type=str, help="Outfile")
    args = parser.parse_args()
    outfile = args.outfile

    probes_list = get_probes()

    fd_out = open(outfile, 'w')
    
    fd_out.write(Probe.header()+'\n')
    for pid, p in probes_list.items():
        if p.is_anchor:
            fd_out.write(str(p)+'\n')

    fd_out.close()

