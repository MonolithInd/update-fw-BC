# update-fw-BC

update-fw-BC.pl : "Update firewall Bad Countries" This is a 
short dirty perl script to update an IPFW to block all 
connections from countries selected by the user that are known
for hacking. It takes one file as input in the CWD dir: 
"ip_lists.txt" which is a file containing a link to files on
ipdeny.com per line. For each IP list it grabs the list 
(a list of CIDR addressed per line) Ingests them, sorts the 
list and then aggrigates networks where posible using 
Net::Netmask. It then inserts these IPs into a IPFW/PF/IPTABLES table.

1.0 FIREWALL REQUIREMENTS
-------------------------
This script only makes a table and fills it with IP address blocks
It is up to the user to have a perminent rule that points to 
the table in your firewall. In IPFW it's a number, in PF a name, in 
iptables it's either a chain or a set. See below for examples on 
how to add the block entry for your firewall package. 

IPFW:
Rule table default is 1. Your firewall rules shoud be of the format:

ipfw -q RULENUM add deny ip from table\(1\) to any
ipfw -q RULENUM add deny ip from any to table\(1\)

choose your own number for "RULENUM" thought I recommend
00001 to makje sure it's always matched first. 
Please note, escaping the "()" is important. If you're already
using table 1 adjust as required including the table number variable
in the script itself. Making the rule perminent
across reboots is left as an exercise for the reader. 

PF:
Add following to pf.conf (default name is badcountries) :

table <badcountries> persist
block on INTERFACE from <badcountries> to any
block on INTERFACE from any to <badcountries>

make sure you repalce INTERFACE with your correct network interface name.

IPTABLES:
NOTE: using stock iptables is exceedingly slow to update chains and
large chains can have exceedingly high impact on system performance. 
If using Linux+iptalbles it is HIGHLY reccomended you install and use 
"ipset" as well. See below for details on IPSET.
 
With iptables and no ipset you only get inbound blocking from the BAD IPs as
the way chains work would requite 2 x rules for each country and 
IPtables struggles as it is with lists this big. If you want in and out 
blocking see "ipset" below.

The following syntax creates the chain, adds it to the input filter and
sets it to deny. Default chain name is badcountries.

iptables -N badcountries
iptables -A INPUT -j badcountries

PLEASE NOTE: Rules insertion takes a really long time on linux 
(because iptables is shit). Script may take 10+  min or more to run 
with large lists of countries and IP blocks. 

IPSET:
ipset is an extension to iptables that allows you to create an in memory
hash of IP addresses of large size that iptables can refrence. It is not 
a firewall in it's own right but rather a store of addresses for iptables
use. To install ipset on ubuntu: 

apt-get install ipset

Set up your ipset rule as follows: 

ipset create badcountries hash:net

Then add your in and outbound rules to iptables: 

iptables -A INPUT -m set --match-set badcountries src -j DROP 
iptables -A OUTPUT -m set --match-set badcountries dst -j DROP

It is up to the reader to make this create last across reboots. 

The script will flush and recreate the ipset when run with 
"-f ipset". This is a MUCH faster insert and results in MUCH (11 times)
better performance of the final firewall. 

See the following URL for details : http://daemonkeeper.net/781/mass-blocking-ip-addresses-with-ipset/

2.0 SOFTWARE REQUIREMENTS
-------------------------
Script depends on Net::Netmask  and LWP::Simple install with:

FREEBSD :
portmaster net-mgmt/p5-Net-Netmask
portmaster www/p5-libwww

UBUNTU: 
apt-get install libnet-netmask-perl
LWP is installed by default. 
If using ipset (highly recommended)
apt-get install ipset

3.0 RUNNING THE SOFTWARE 
------------------------

Update firewall Bad Country options:
-h : This help
-v : Print version info
-q : Quiet mode, disable all standard output. Used for running from CRON.
-f : specify firewall type, can be ipfw, pf, iptables or ipset

example on Freebsd with PF:

./update-fw-BC.pl -f pf

example of running from cron daily a2 2am with IPFW

0 2 * * * PATHTOPROGRAM/update-fw-BC.pl -q -f ipfw

4.0 OTHER INFO
-------------- 
v1.0 : Basic ipfw support

v1.1 : Added pf and iptables support

v1.2 : Added ipset support

Written by Sebastian Kai Frost. sebastian.kai.frost@gmail.com
