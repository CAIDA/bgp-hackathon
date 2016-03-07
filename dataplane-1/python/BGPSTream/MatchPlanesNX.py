import math
import radix
import editdistance
# import networkx as nx
# import matplotlib.pyplot as plt
import sys
import json


class StateMatcher(object):
    def __init__(self):
        # self.trace_bgp_math_graph = nx.DiGraph()
        self.prefix_radix = radix.Radix()
        # self.pref_d_c = {}
        self.pref_c_d = {}

        ifp = '../../atlas/anchor_prefix.txt'
        br = open(ifp, 'rb')
        for l in br:
            self.prefix_radix.add(l.strip())

        self.trace_state = {}
        path = '../../data/aspaths-traceroutes-2'
        br = open(path, 'rb')
        for l in br:
            tokens = l.split()
            if len(tokens) <= 2:
                continue
            pref = self.prefix_radix.search_best(tokens[0])
            try:
                pref = pref.prefix
            except AttributeError:
                print l
                raw_input('???')
            asn = tokens[1]
            as_path = ' '.join(tokens[2:])
            if pref not in self.trace_state:
                self.trace_state[pref] = {}
            self.trace_state[pref][asn] = as_path

        self.bgp_state = {}
        path = '../../data/rib'
        br = open(path, 'rb')
        for l in br:
            tokens = l.split()
            # pref = self.prefix_radix.search_best(tokens[2])
            # pref = pref.prefix
            pref = tokens[2]
            collector = ':'.join(tokens[0:2])
            as_path = ' '.join(tokens[3:])
            if pref not in self.bgp_state:
                self.bgp_state[pref] = {}
            self.bgp_state[pref][collector] = as_path

        # print self.trace_state
        # print self.bgp_state

    def recalculate(self, vp_c, pref, aspath_c):
        print vp_c, pref, aspath_c
        try:
            vp_aspth_dict_d = self.trace_state[pref]
        except KeyError:
            print '>>> missing traces in data plane to prefix {0} <<<'.format(pref)
            return
        if pref not in self.pref_c_d:
            self.pref_c_d[pref] = {}
        for vp_d, aspath_d in vp_aspth_dict_d.iteritems():
            dist = editdistance.eval(aspath_c.split(), aspath_d.split())

            if vp_c not in self.pref_c_d[pref]:
                self.pref_c_d[pref][vp_c] = {}
            self.pref_c_d[pref][vp_c][vp_d] = [dist, max(len(aspath_d.split()), len(aspath_c.split()))]

    def match_states(self):
        for pref_d, vp_aspth_dict_d in self.trace_state.iteritems():
            print pref_d
            # if pref_d not in self.pref_d_c:
            #     self.pref_d_c[pref_d] = {}
            if pref_d not in self.pref_c_d:
                self.pref_c_d[pref_d] = {}
            best_match_val = sys.maxint
            best_match_lst = []
            # raw_input('...')
            for vp_d, aspath_d in vp_aspth_dict_d.iteritems():
                # if vp_d not in self.pref_d_c[pref_d]:
                #     self.pref_d_c[pref_d][vp_d] = {}

                vp_aspth_dict_c = self.bgp_state[pref_d]
                for vp_c, aspath_c in vp_aspth_dict_c.iteritems():
                    dist = editdistance.eval(aspath_c.split(), aspath_d.split())

                    # self.pref_d_c[pref_d][vp_d][vp_c] = [dist, max(len(aspath_d.split()), len(aspath_c.split()))]

                    if vp_c not in self.pref_c_d[pref_d]:
                        self.pref_c_d[pref_d][vp_c] = {}
                    # if vp_d not in self.pref_c_d[pref_d][vp_c]:
                    #     self.pref_c_d[pref_d][vp_c][vp_d] = {}
                    self.pref_c_d[pref_d][vp_c][vp_d] = [dist, max(len(aspath_d.split()), len(aspath_c.split()))]

                    if dist < best_match_val:
                        best_match_val = dist
                        best_match_lst = [vp_c]
                    elif dist == best_match_val:
                        best_match_lst.append(vp_c)
                    # print vp_d, '%', vp_c, '=>', editdistance.eval(aspath_c.split(), aspath_d.split())
                # print vp_d, '%', best_match_val, '=>', best_match_lst
                """ NetworkX """
                # for vp_c in best_match_lst:
                #     self.trace_bgp_math_graph.add_edge('d_{0}_{1}'.format(vp_d, pref_d), 'd_{0}_{1}'.format(vp_c, pref_d))

    def show_graph(self):
        # print len(self.trace_bgp_math_graph.nodes())
        # print len(self.trace_bgp_math_graph.edges())
        # nx.draw_spectral(self.trace_bgp_math_graph, node_size=10, alpha=0.5, with_labels=False)
        # plt.savefig('matching_graph', bbox_inches='tight', format='jpg', dpi=320)
        # plt.show()

        # ofp = u'./data/matching.txt'
        # with open(ofp, 'w') as outfile:
        #     json.dump(self.pref_c_d, outfile, indent=4, separators=(',', ': '))

        ofp = '../../data/matching_pref-ctrl-data.txt'
        with open(ofp, 'w') as outfile:
            json.dump(self.pref_c_d, outfile, indent=4, separators=(',', ': '))

    def keep_updating(self):
        # print json.dumps(self.bgp_state['202.52.0.0/23'])[:100]
        # print json.dumps(self.bgp_state['202.52.0.0/23']['route-views.wide:202.249.2.86'])[:100]
        ipath = '../../data/stream_1454198400'
        br = open(ipath, 'rb')
        for l in br:
            tokens = l.split('\t')
            collector = ':'.join([tokens[0], tokens[1]])
            prefix = tokens[3]
            new_aspath = tokens[4]
            old_aspth = 'Nan'
            if prefix not in self.bgp_state:
                continue

            if collector in self.bgp_state[prefix]:
                old_aspth=self.bgp_state[prefix][collector]

            print collector, prefix
            print '\tnew: ', new_aspath
            print '\told: ', old_aspth

            self.bgp_state[prefix][collector] = new_aspath
            self.recalculate(collector, prefix, new_aspath)

if __name__ == '__main__':
    sm = StateMatcher()
    sm.match_states()
    sm.keep_updating()

    # sm.show_graph()
