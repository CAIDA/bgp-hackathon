#!/usr/bin/env python
#
#
# Copyright (C) 2015 The Regents of the University of California.
# Authors: Alistair King, Chiara Orsini
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.
#

import pickle,os.path
from collections import defaultdict
from netaddr import IPNetwork, IPAddress, IPSet

global hitlist
global hotlist
global hitlistCache
global hotlistCache

hitlist = IPSet([])
hotlist = defaultdict(list)
hitlistCache="hitlist.cache"
hotlistCache="hotlist.cache"


# Helper functions


def load_data_files():
    ''' 
        Load data from either flat-files or python pickles
    '''
    global hitlist,hotlist
    global hotlistCache,hitlistCache
    if os.path.isfile(hitlistCache): #Load pickled ipset
        print "reading hitlist from cache"
        hitlist = pickle.load( open( hitlistCache, "rb" ) )
        print "done"
    else: 
        print "reading hitlist from text file"
        #hitlist = [line.rstrip() for line in open('hitlist.txt')]
        hitlist_str = [line.rstrip() for line in open('hitlist_100000.txt')]
        hitlist = IPSet(hitlist_str)

        #Save this for next run
        pickle.dump( hitlist, open( hitlistCache, "wb" ) )

        print "done"


    if os.path.isfile(hotlistCache): #Load pickled prefix->ip map
        print "reading hotlist from cache"
        hotlist = pickle.load( open( hotlistCache, "rb" ) )
        print "done"
    else: 
        hotlist = defaultdict(list) 




def get_hitlist_ips(prefix_list):
    ''' 
        For each prefix (dict - prefix:count), 
        check if any IP from the hitlist is in the prefix. 
        Return a dict of prefix:list of stable IPs

        For caching/speed purposes, prefixes with no IPs are stored with zero-length lists
    '''
    global hitlist #IPSet
    global hotlist #dict - prefix:[ip]
    global hotlistCache

    newHotlist=defaultdict(list)

    #TESTING: hitlist does not change often -- determine cached hitlist ips
    known_prefixes = IPSet(hotlist.keys()) & IPSet(prefix_list.keys()) #known prefix list
    print known_prefixes

    #Whatever remains is our unknown prefix set
    unknown_prefixes = IPSet(prefix_list.keys()) - IPSet(hotlist.keys()) #unknown prefix list

    
    if unknown_prefixes.size == 0: #nothing new, return current
        print "no new prefixes, returning cached hotlist"
        return hotlist

    #Determine which prefixes need examination
    intersection = hitlist & unknown_prefixes
    #This may take *many* seconds to compute, but fast compared to iteration

    newHotlist = get_prefix_map(intersection,prefix_list)
    
    merged = merge_two_dicts(hotlist,newHotlist) 

    #Cache the current set to disk
    pickle.dump( merged, open( hotlistCache, "wb" ) )

    return merged

def merge_two_dicts(x, y):
    '''Given two dicts, merge them into a new dict as a shallow copy.'''
    z = x.copy()
    z.update(y)
    return z

def get_prefix_map(ip_list,prefix_list):
    '''
        Iterate and catalog only the intersection set -- 
        The intersection will consist of individual IP addresses 
        We still need to map each to one of the specified CIDR blocks they matched
    '''
    retval=defaultdict(list)

    for ip in ip_list:
        for prefix in prefix_list:
            if IPAddress(ip) in IPSet(IPNetwork(prefix)):
                retval[prefix].append(str(ip))
            else:
                retval[prefix]=[]

    return retval


test_prefix_list=dict()

test_prefix_list={
    '214.115.88.0/24': 100,
    '85.215.33.0/24': 100,
    '134.134.68.0/24': 100,
    '176.171.32.0/24': 100,
    '214.115.88.0/24': 100,
    '200.0.251.0/24': 325,
    '157.52.204.0/24': 108,
    '61.12.46.0/24': 100,
    '61.12.95.0/24': 100,
    '2a06:9380::/29': 92,
    '206.208.95.0/24': 85,
    '93.181.192.0/19': 83,
    '168.128.73.0/24': 80,
    '2804:14d:8080::/48': 79
}

load_data_files()

newHotlistMap = get_hitlist_ips(test_prefix_list)

print newHotlistMap 
