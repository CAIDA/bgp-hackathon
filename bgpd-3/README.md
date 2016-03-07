# bgp-hackathon

The 1st BGP Hackathon will be held February 6-7, 2016 (just before NANOG 66 and the CAIDA AIMS workshop) in San Diego, CA. Details are available at the [BGP Hackathon webpage](http://www.caida.org/workshops/bgp-hackathon/1602/) and the [BGP Hackathon Wiki](https://github.com/CAIDA/bgp-hackathon/wiki)

Objective:
  Read a BGP live stream from CAIDA or MRT file and insert them into a BGP session

What we need:
  bgpreader from the bgpstream core package provided by Caida
  bgp_simple-v2.pl 
  Perl modules for the project

Overview:
  We will read the BGP live stream feed using bgpreader, then the standard ouput of it will be redirected to a pipe file (mkfifo) where a perl script called bgpsimple-v2 will be reading this file. This very same script will stablished the BGP session againts a BGP speaker and announce the prefixes received in the stream. 

LAB Topology:
  The configuration was already tested againts Bird
  Linux box ---> Bird 

Summary of our work:
  - Lab topology creation
  - Addition of the ADD-PATH capability to the Net::BGP perl modules
  - Addition of IPv6 support to the Net::BGP perl modules
  - Some hacks to the original bgpsimple perl script (original author unknown)

Why ADD-PATH Capability?
  If not add-path capability is used then only the latest prefix received by the router will be kept. 
  Using ADD-PATH will keep all path in the BGP Table to reach certain a prefix.
  As an example, caida-bmp project has several sources, all those updates are read by bgpreader.

Limitations:
  This project only works for BGP Speakers with the add_path BGP Capability
 
How does it works?
  bgpreader has the ability to write his output in the -m format used by libbgpdump (by RIPENCC), this is the very same format bgpsimple uses as stdin. That's why myroutes is a PIPE file (created with mkfifo). 
  bgpsimple-v2 can also read regular files using the -p (then it's not necessary bgpreader)

Steps:  

INSTALL BGP READER - UBUNTU 15.04

First install general some packages:
apt-get install apt-file libsqlite3-dev libsqlite3 libmysqlclient-dev libmysqlclient
apt-get install libcurl-dev libcurl  autoconf git libssl-dev
apt-get install build-essential zlib1g-dev libbz2-dev 
apt-get install libtool git
apt-get install zlib1g-dev

Also intall wandio
wandio-1.0.3
git clone https://github.com/alistairking/wandio

./configure

cd wandio
./bootstrap.sh
./configure && ./make && ./make install
wandiocat http://www.apple.com/library/test/success.html

to test wandio:
wandiocat http://www.apple.com/library/test/success.html

Download bgp reader tarball from:
https://bgpstream.caida.org/download

#ldconfig (before testing)

#mkfifo myroutes

to test bgpreader:
./bgpreader -p caida-bmp -w 1453912260 -m
(wait some seconds and then you will see something)

# git clone https://github.com/xdel/bgpsimple


Finally run everything:.
In two separate terminals (or any other way you would like to do it):

./bgpreader -p caida-bmp -w 1453912260 -m > /usr/src/bgpsimple/myroutes
./bgp_simple.pl -myas 65000 -myip 192.168.1.2 -peerip 192.168.1.1 -peeras 65000 -p myroutes 


One more time, what will happen behind this?
bgpreader will read an online feed from a project called caida-bmp with starting timestamp 1453912260 (Jan 27 2016, 16:31) in "-m" format, It means a libbgpdump format (see references). The stardard output of all this will be send to the file /usr/src/bgpsimple/myroutes which is a "pipe file". At the same time, bgp_simple.pl will create an iBGP session againts peer 192.168.1.1/AS65000 (a bgp speaker such as Quagga or Cisco). bgp_simple.pl will read myroutes files and send what it seems in this file thru the iBGP Session. 

Important information:
- The BGP Session won't be stablished until there is something in the file myroutes
- eBGP multi-hop session are allowed
- You have to wait short time (few seconds) until bgpreaders start to actually see something and bgp_simple.pl starts to announce to the BGP peer



References / More information:
-Part of the work was based on:
http://evilrouters.net/2009/08/21/getting-bgp-routes-into-dynamips-with-video/

- Caida BGP Stream:
https://bgpstream.caida.org/

- bgpreader info:
https://bgpstream.caida.org/docs/tools/bgpreader

- RIPE NCC libbgpdump:
http://www.ris.ripe.net/source/bgpdump/

- Introduction of "Named Pipes" (pipe files in Linux):
http://www.linuxjournal.com/article/2156




