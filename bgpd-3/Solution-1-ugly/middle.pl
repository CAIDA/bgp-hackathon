#!/usr/bin/perl
use strict;

# TODO: written too fast, make it better (there are many assumptions on the environment)
# see TODO below

die ("Usage: $0 input_file routing_suite (bird|quagga)\n") if ($#ARGV lt 1);

my $file = $ARGV[0];
my $RCS = $ARGV[1];
my %Peers = ();
my $n_peers = 0;

open INPUT, $file or die $!;

while (<INPUT>) {
    chomp;
    my $line = $_;
    my @fields = split /\|/, $line;
    my $peer_ip = $fields[3];
    next if ($peer_ip =~ /\:/); # TODO no ipv6 for the moment
    next if ($peer_ip !~ /\d/);
    if (! exists $Peers{$peer_ip}) {
        print "Will open a new session for $peer_ip\n";
        my $pipe_file = "routes_${peer_ip}";
        system("touch $pipe_file");
        $Peers{$peer_ip} = $pipe_file;
        $n_peers++;
        my $fake_peer_IP = "192.168.1.$n_peers"; # TODO: no more than 255 peers
        system("ip addr add $fake_peer_IP dev eth0");
        my $fake_peer_AS = 65000+$n_peers;
        print "Adding session for $peer_ip - $fake_peer_IP\n";
        if ($RCS =~ /bird/i) {
            my $ID = "P$n_peers";    
            system("./add_neighbor_bird.sh $ID $fake_peer_IP $fake_peer_AS ../bird.conf"); # TODO bird.conf could be anywhere
            # reload bird configf
            system("birdc configure > /dev/null 2>&1"); # TODO need to be root for now
            sleep 1;
        } elsif ($RCS =~ /quagga/i) {
            system("./add_neighbor_quagga.sh $fake_peer_IP $fake_peer_AS 5 127.0.0.1 IPv4");
            sleep 5;
        }
        
        # start bgp_simple
        # TODO: please remove absolute path to bgp_simple !
        system("nohup /home/luca/bgpsimple-master/bgp_simple.pl -myas $fake_peer_AS -myip $fake_peer_IP -peerip 127.0.0.1 -peeras 65517 -p ".$Peers{$peer_ip}." -nolisten > /dev/null 2>&1 &");
        #print "BGP simple started\n";
    }
    next if $line =~ /Error/;
    #print "Dispatching in $Peers{$peer_ip} $line\n";
    system("echo \"$line\" >> $Peers{$peer_ip}");
}

close INPUT;
