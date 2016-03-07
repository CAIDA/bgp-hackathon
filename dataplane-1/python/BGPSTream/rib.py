from sets import Set

class Rib:

    def __init__(self, rib_fd, up_fd):
        self.rib = {}
        self.rib_fd = rib_fd
        self.up_fd = up_fd
        self.is_flushed = False

    def add_to_rib(self, collector, peer_ip, prefix, ts, as_path):
        if collector not in self.rib:
            self.rib[collector] = {}
        if peer_ip not in self.rib[collector]:
            self.rib[collector][peer_ip] = {}
        if self.is_flushed and prefix in self.rib[collector][peer_ip]:
            if self.rib[collector][peer_ip][prefix] != as_path:
                self.up_fd.write(str(collector)+'\t'+str(peer_ip)+'\t'+str(ts)+'\t'+str(prefix)+'\t'+str(self.rib[collector][peer_ip][prefix])+'\t'+str(as_path)+'\n')
        self.rib[collector][peer_ip][prefix] = as_path

    def remove_from_rib(self, collector, peer_ip, prefix, ts):
        try:
            if self.is_flushed and prefix in self.rib[collector][peer_ip]:
                self.up_fd.write(str(collector)+'\t'+str(peer_ip)+'\t'+str(ts)+'\t'+str(prefix)+'\t'+str(self.rib[collector][peer_ip][prefix])+'\t'+"W"+'\n')
            try:
                self.rib[collector][peer_ip].pop(prefix, None)
            except KeyError:
                #print "KeyError"
                pass
        except KeyError:
            pass

    def flush(self):
        if not self.is_flushed:
            self.is_flushed = True
            self.rib_fd.write(str(self))

    def __str__(self):
        res_string = ''
        for c in self.rib:
            for peer_ip in self.rib[c]:
                for prefix, as_path in self.rib[c][peer_ip].items():
                    res_string += str(c)+'\t'+str(peer_ip)+'\t'+str(prefix)+'\t'+str(as_path)+'\n'

        return res_string

    
