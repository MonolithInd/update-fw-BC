# update-fw-BC

update-fw-BC.pl : "Update firewall Bad Countries" This is a 
short perl script to insert rules into a firewall. The purpose 
is to block all connections from countries selected by the 
user that are known for hacking. 

It takes one file as input in the CWD dir: "ip_lists.txt" 
which is a file containing links to files on
ipdeny.com per line. These files are aggrigated lists
of netblocks known to be in that country.

For each link it grabs the list, ingests it, sorts the 
netblocks and then aggrigates them again where posible using 
Net::Netmask. It then inserts these IPs into a firewall.

Currently supported is : IPFW, PF, IPTABLES, IPTABLES+IPSET

1.0 SETTING UP YOUR LISTS
-------------------------
Included in the package is an example file ip_lists.txt. 

The script grabs each list in the text file (you can add your own from: http://ipdeny.com/ipblocks/

Just copy the aggrigated zones link and paste  it into a line in the file. 

By default in the file there are links for Brazil, China, India, Israel,
Romania, Russia, Turkey, Uzbekistan and the Ukrane. All on the top 10 
hacking countries source lists.

2.0 FIREWALL REQUIREMENTS
-------------------------
This script only creates a table and fills it with IP address blocks
It is up to the user to have a perminent rule that points to 
the table in your firewall. In IPFW the table is a number, in PF a name, in 
iptables it's either a named chain or a set. See below for examples on 
how to add these required block entry for your firewall package. The reader
will have to make these entries static across reboots (PF does by default in pf.conf)

<b>IPFW:</B></br>
Default rule table is 1. Your firewall rules shoud be of the format:

* ipfw -q RULENUM add deny ip from table\\(1\\) to any
* ipfw -q RULENUM add deny ip from any to table\\(1\\)

...choose your own number for "RULENUM". 

I recommend using 00001 to make sure it's always matched first. 

Please note: using "\" to escape the prenthesis "()" is important. 

If you're already using table 1 adjust as required. Do not forget to
change the table number variable
in the script itself. 

Making the rule perminent
across reboots is left as an exercise for the reader. 

<b>PF:</b> </br>
Add following to pf.conf (default name is badcountries) :

* table \<badcountries\> persist
* block on INTERFACE from \<badcountries\> to any
* block on INTERFACE from any to \<badcountries\>

make sure you repalce INTERFACE with your correct network interface name.

<b>IPTABLES:</b></br>
NOTE: using stock iptables is exceedingly slow to update chains and
large chains can have exceedingly high impact on system performance. 
If using Linux+iptalbles it is HIGHLY reccomended you install and use 
"ipset" as well. See below for details on IPSET.
 
With iptables and no ipset you will only get inbound blocking from bad IP blocks
This is due to the the way chains work that would requite 2 x rules for each country. 
IPtables already struggles with lists this big. If you want both in and out 
blocking see "ipset" below.

The following syntax creates the chain, adds it to the input filter and
sets it to deny. Default chain name is badcountries.

* iptables -N badcountries
* iptables -A INPUT -j badcountries

PLEASE NOTE: Rules insertion takes a really long time on linux 
(because iptables is crap). Script may take 10+  min or more to run 
with large lists of countries and IP blocks. 

<b>IPSET:</b></br>
ipset is an extension to iptables that allows you to create an in memory
hash of IP addresses of arbitrary size that iptables can refrence. It is not 
a firewall in it's own right but rather a store of addresses for iptables
use. To install ipset on ubuntu: 

* apt-get install ipset

Set up your ipset rule as follows: 

* ipset create badcountries hash:net

Then add your in and outbound rules to iptables: 

* iptables -A INPUT -m set --match-set badcountries src -j DROP 
* iptables -A OUTPUT -m set --match-set badcountries dst -j DROP

It is up to the reader to make these last across reboots. 

The script will flush and recreate the ipset when run. 
This is a MUCH faster insert and results in MUCH (11 times)
better performance of the final firewall. 

See the following URL for details on IPSET and IPTABLES: http://daemonkeeper.net/781/mass-blocking-ip-addresses-with-ipset/

3.0 SOFTWARE REQUIREMENTS
-------------------------
Script depends on Net::Netmask  and LWP::Simple install with:

FREEBSD :

With Portmaster:
* portmaster net-mgmt/p5-Net-Netmask
* portmaster www/p5-libwww

With PKG: 
* pkg install net-mgmt/p5-Net-Netmask
* pkg install www/p5-libwww

It is assumed the user already has PERL installed. 

UBUNTU: 
* apt-get install libnet-netmask-perl
* LWP is usually already installed by default. 

If using ipset (highly recommended)
* apt-get install ipset

4.0 RUNNING THE SOFTWARE 
------------------------

Update firewall Bad Country options:
* -h : This help
* -v : Print version info
* -q : Quiet mode, disable all standard output. Used for running from CRON.
* -f : specify firewall type, can be ipfw, pf, iptables or ipset

If the scripts doesn't run out of the box on your system there are a few
things you can check:
* Make sure your firewall command is where the script expects it to be. If not you can edit the script. The paths for each of the firewall types are defined as variables at the top of the script.
* If the script doens't run at all make sure you have PERL installed and the script is refrenceing the right path for the binary.
* If you're having any other major problems don't hesitate to contact me on the address below. 

example running on Freebsd with PF:

* ./update-fw-BC.pl -f pf

example of running from cron daily at 2am with IPFW

* 0 2 * * * PATHTOPROGRAM/update-fw-BC.pl -q -f ipfw

5.0 OTHER INFO
-------------- 
* v1.0 : Basic ipfw support
* v1.1 : Added pf and iptables support
* v1.2 : Added ipset support

6.0 DISCLAIMER
--------------
This script is provided "as is". I am in no way responsible if you use this script and it locks you out of your server on the other side of the planet, starts world war 3 or causes a global burrito shortage. 

Written by Sebastian Kai Frost. sebastian.kai.frost@gmail.com
