# update-fw-BC

update-fw-BC.pl : "Update firewall Bad Countries" This is a
short perl script to insert rules into a firewall. The purpose
is to block all connections from countries selected by the
user that are known for hacking.

It either takes 
* one file as input in the CWD dir: "ip_lists.txt" which is a file containing links to files on ipdeny.com per line. These files are aggregated lists of netblocks known to be in that country.
* a user supplied file containing one IP address/netmask entry per line in the format x.x.x.x/xx

For each link it grabs the list, ingests it, sorts the
netblocks and then aggregates them again where posible using
Net::Netmask. It then inserts these IPs into a firewall.

Currently supported is : IPFW, PF, IPTABLES, IPTABLES+IPSET, NFTABLES

1.0 SETTING UP YOUR LISTS
-------------------------
Included in the package is an example file ip_lists.txt.

The script grabs each list in the text file (you can add your own from: http://ipdeny.com/ipblocks/

Just copy the aggregated zones link and paste  it into a line in the file.

By default in the file there are links for Brazil, China, India, Israel,
Romania, Russia, Turkey, Uzbekistan and the Ukraine. All on the top 10
hacking countries source lists.

2.0 FIREWALL REQUIREMENTS
-------------------------
This script only creates a table and fills it with IP address blocks.
It is up to the user to have a permanent rule that points to
the table in your firewall. In IPFW the table is a number, in PF a name, in
iptables it's either a named chain or a set. See below for examples on
how to add these required block entries for your firewall package. The reader
will have to make these entries static across reboots (PF does by default in pf.conf)

<b>IPFW:</B></br>
Default "table number" is 1. Your firewall rules should be of the format:

    ipfw -q RULENUM add deny ip from table\(1\) to any
    ipfw -q RULENUM add deny ip from any to table\(1\)

...choose your own "rule number" for "RULENUM". Note : the rule number is different to the table number.
The "table number" (in this case "1") is a table refrence for storing the bad IP's. The "rule number" is the rule that points at this table, lower numbers are higher up in the firewall.

I recommend using rule number 00001 to make sure it's always the first rule and matched first.

Please note: using "\\" to escape the parentheses "()" is important.

If you're already using table 1 for something else, adjust as required, but do not forget to
change the table number variable in the script itself.

Making the rule persistent across reboots is left as an exercise for the reader.

<b>PF:</b> </br>
Add following to pf.conf (default name is badcountries) :

    table \<badcountries\> persist
    block on INTERFACE from \<badcountries\> to any
    block on INTERFACE from any to \<badcountries\>

Make sure you replace INTERFACE with your correct network interface name. Putting this in pf.conf should
make it static across reboots.

<b>IPTABLES:</b></br>
NOTE: using stock iptables is exceedingly slow to update chains and
large chains can have exceedingly high impact on system performance.
If using Linux+iptalbles it is HIGHLY reccomended you install and use
"ipset" as well. See below for details on IPSET.

With iptables and no ipset you will only get inbound blocking from bad IP blocks
This is due to the the way chains work that would require 2 x rules for each country.
IPtables already struggles with lists this big. If you want both in and out
blocking see "ipset" below.

In iptables we create a custom chain and put the block commands in there. Then simply point at the chain from the default INPUT chain which matches all inbound packets. The block command itself is inserted by the script as part of insertion into the custom chain.

The following syntax creates the chain, adds it to the input filter. Default chain name is badcountries.

    iptables -N badcountries
    iptables -A INPUT -j badcountries

PLEASE NOTE: Rules insertion takes a really long time on linux
(because iptables is crap). Script may take 10+  min or more to run
with large lists of countries and IP blocks.

<b>NFTABLES</b></br>
Nftables has the concept of "sets" like IPSET built into the base firewall package. As such we can create a set as part of the tables and refer to it in rules.

In nftables we create a custom set called "country_block" and place the full IP list of the bad countries in this set. To create this set see the command below.

    nft add set filter country_block { type ipv4_addr \; flags interval \;}

Once the set is created we can run the script with -f nftables and the set is populated. Unlike iptables/ipset this set is displayed as part of the ruleset when it is listed. Be prepared for a long list of IPs. Once created and populated the set can be referenced anywhere in your nftables rules. As an example:

    chain input {
		type filter hook input priority 0; policy accept;
		ip saddr @country_block counter drop
    }

Note, to increase speed when run for nftables the script creates a file, writes the IPs to the file then injects the file into the nftables set. Rather than adding the items line by line which I have found is slow. As such the script will need to run as a user with access to /tmp for the file creation and deletion during set loading.

Making these firewall changes static across reboots is left as an exercise for the reader.

<b>IPSET:</b></br>
ipset is an extension to iptables that allows you to create an in memory
hash of IP addresses of arbitrary size that iptables can refrence. It is not
a firewall in its own right but rather a store of addresses for iptables
to use. To install ipset on ubuntu:

    apt-get install ipset

To install ipset on Red Hat variants:

    yum install ipset

Set up your ipset rule as follows:

    ipset create badcountries hash:net

Then add your in and outbound rules to iptables:

    iptables -A INPUT -m set --match-set badcountries src -j DROP
    iptables -A OUTPUT -m set --match-set badcountries dst -j DROP

Note that in this scenario the ipset memory list is just a list of IPs the match and the drop command is inserted as a line into the INPUT and OUTPUT chains explicitly.

It is up to the reader to make these persistent across reboots.

The script will flush and recreate the ipset when run.
This is a MUCH faster insert and results in MUCH (11 times)
better performance of the final firewall.

See the following URL for details on IPSET and IPTABLES: http://daemonkeeper.net/781/mass-blocking-ip-addresses-with-ipset/

3.0 SOFTWARE REQUIREMENTS
-------------------------
Script depends on Net::Netmask  and LWP::Simple install with:

FREEBSD :

With Portmaster:

    portmaster net-mgmt/p5-Net-Netmask
    portmaster www/p5-libwww

With PKG:

    pkg install net-mgmt/p5-Net-Netmask
    pkg install www/p5-libwww

It is assumed the user already has PERL installed.

UBUNTU:

    apt-get install libnet-netmask-perl
    apt-get install libwww-perl

If using ipset (highly recommended):

    apt-get install ipset

REDHAT variants:

You may need to install Net::Netmask:

    yum install perl-Net-Netmask.noarch


4.0 RUNNING THE SOFTWARE
------------------------

Update firewall Bad Country options:

    -h : This help
    -v : Print version info
    -q : Quiet mode, disable all standard output. Used for running from CRON.
    -f : specify firewall type, can be ipfw, pf, iptables, nftables or ipset (ipset is recommended if using iptables)
    -l : specify an IP lists file to import your own IP list. See README for format

If the scripts don't run out of the box on your system there are a few
things you can check:
* Make sure your firewall command is where the script expects it to be. If not you can edit the script. The paths for each of the firewall types are defined as variables at the top of the script.
* If the script doesn't run at all make sure you have PERL installed and the script is refrenceing the right path for the binary.
* If you're having any other major problems don't hesitate to contact me on the address below.

example running on Freebsd with PF:

     ./update-fw-BC.pl -f pf

example of running from cron daily at 2am with IPFW

    * 0 2 * * * /PATH/TO/PROGRAM/update-fw-BC.pl -q -f ipfw

You can verify that the insertion worked in the following way:

* IPFW: "ipfw table 1 list"
* PF: "pfctl -t badcountries -T show"
* IPTABLES: "iptables -L"
* IPSET: "ipset list badcountries"
* NFTABLES: "nft list set filter country_block"

As of version 1.4 I have added the option to specify your own list of IP addresses for the script to import. There is an example file in the package but it must be of the format:

    x.x.x.x/xx 
    
With one IP of the above format per line. Similar to the lists from IPdeny. Currently the script does NO vlaidation on your IP addresses before trying to import them, so as it stands if you mi-type it will just silently fail. I will fix this in a new version soon. It's about time for a total re-write to make it not messy anyway. 

5.0 OTHER INFO
--------------
* v1.0 : Basic ipfw support
* v1.1 : Added pf and iptables support
* v1.2 : Added ipset support
* v1.3 : Added nftables support
* v1.4 : Added support for user specified IP list files.

6.0 DISCLAIMER
--------------
This script is provided "as is". I am in no way responsible if you use this script and it locks you out of your server on the other side of the planet, starts world war 3 or causes a global burrito shortage.

Written by Sebastian Kai Frost. sebastian.kai.frost@gmail.com
