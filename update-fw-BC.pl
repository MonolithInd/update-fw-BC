#!/usr/local/bin/perl -w 
###################################################################
###################################################################
## update-fw-BC.pl : "Update firewall Bad Countries" This is a 
## short dirty perl script to update an IPFW to block all 
## connections from countries selected by the user that are known
## for hacking. It takes one file as input in the CWD dir: 
## "ip_lists.txt" which is a file containing a link to files on
## ipdeny.com per line. For each IP list it grabbs the list 
## (a list of CIDR addressed per line) Ingests them, sorts the 
## list and then aggrigates networks where posible using 
## Net::Netmask. It then inserts these IPs into a IPFW table.
##
## It is up to the user to have a rule that points to the table 
## in your firewall. In IPFW it's a number. in PF a name.
## 
## PLEASE READ THE README FILE FOR HOW TO RUN AND REQUIRED
## FW RULES AND LIBRARIES
## 
## v1.0 : Basic ipfw support
## v1.1 : Added pf and iptables support
##
## Written by Sebastian Kai Frost. sebastian.kai.frost@gmail.com
##

use strict;
use LWP::Simple;
use Getopt::Std;
use Net::Netmask; 

# set base varaibles. 
my $version = "v1.2";
my %options = ();
my $ipLists = "ip_lists.txt";
my $firewall = "";
my $ipfwpath = "/sbin";
my $iptablespath = "/sbin";
my $pfpath = "/sbin";
my $ipsetpath = "/sbin";
# below is the table you're insertign the rules into. You must refrence 
# this table in a rule somewhere or the script does nothing. 
my $ipfwtable = 1;
my $pftable = "badcountries";
my $iptableschain = "badcountries";
my $quiet = 0;
my $listsFH;
my @chars = qw(| / - \ );
my $count;
my $row;
my $content;
my $beforecount;
my $aftercount;
my @tempblocks;
my @ipblocks;
my @ipblockOBJ;
my $ip;
my $mask;

parseopts();

print "\n*** Update firewall Bad Country $version ***\n\n" unless ($quiet); 

unless ($firewall) {
	print "No firewall specified, defaulting to IPFW\n\n" unless ($quiet);
	$firewall = "ipfw";
}

print "Updateing firewall - $firewall\n" unless ($quiet);
print "------------------\n" unless ($quiet);

print "-- Grabbing IP Lists and extracting IP blocks...\n" unless ($quiet);

open($listsFH, '<:encoding(UTF-8)', $ipLists) or die "Could not open file '$ipLists' $!";

# run through each of the URLs of IP blocks and grab them, then shove each IP block in 
# a list. 
while ($row = <$listsFH>) {
	chomp $row;
	$content = get($row) or die 'Unable to get page';
	@tempblocks = split(/\n/, $content);
	foreach (@tempblocks) {
		push @ipblocks, $_;
	}	
}
close $listsFH;

print "  -- Done\n" unless ($quiet);

# sort the list into an ordered list. I don't specifically know that net::netmask requires 
# the blocks to be adjacent to merge. But lets not risk it. 
@ipblocks = sort(@ipblocks);

# count how many networks we have to start with so we can compare with after and feel good aobut 
# our efficiency.
$beforecount = @ipblocks;

# create an array of Net::Netmask objects for it to work with. 
foreach (@ipblocks) {
	push @ipblockOBJ, Net::Netmask->new($_);
}

print "-- Aggrigating networks...\n" unless ($quiet);
# aggrigate the networks. 
@ipblockOBJ = cidrs2cidrs(@ipblockOBJ);
# count how many we have now. Look how shiny Net::Netmask is!
$aftercount = @ipblockOBJ;
print "  -- Done\n" unless ($quiet);
print "  -- Networks before/after aggrigation : $beforecount/$aftercount\n" unless ($quiet);

# lets go update our firewall.
print "-- Updateing firewall...\n" unless ($quiet);

#flush out the old list.
print "  -- Flushing old rules...\n" unless ($quiet);
if ($firewall eq "ipfw") {
	system "$ipfwpath/ipfw table $ipfwtable flush";
} elsif ($firewall eq "pf") {
	system "$pfpath/pfctl -q -t $pftable -T flush";
} elsif ($firewall eq "iptables") {
	system "$iptablespath/iptables -F $iptableschain";
} elsif ($firewall eq "ipset") {
	system "$ipsetpath/ipset flush $iptableschain";
} else {
	print "Unknown firewall type\n";
	exit(1);
}
print "  -- Done\n" unless ($quiet);

# go through and put in the new rules. Lets give the user a nice progress bar to go with it
# as this can take a long time. Also a spinning wheel so if they manage to firewall themselves
# out they will see pretty quickly. 
$count = 1;
foreach (@ipblockOBJ) {
	$ip = $_->base();
	$mask = $_->bits();
	if ($firewall eq "ipfw") {
		system("$ipfwpath/ipfw table $ipfwtable add $ip/$mask");
	} elsif ($firewall eq "pf") {
		system("$pfpath/pfctl -q -t $pftable -T add $ip/$mask");
	} elsif ($firewall eq "iptables") {
		system("$iptablespath/iptables -A $iptableschain -s $ip/$mask -j DROP");
	} elsif ($firewall eq "ipset") {
		system("$ipsetpath/ipset add $iptableschain $ip/$mask");
	} else {
		print "Unknown firewall type\n";
		exit(1);
	}
	progress_bar( $count, $aftercount, 25, '=' );
	$count++;
}

print "\n" unless ($quiet);
print "  -- Done\n" unless ($quiet);
print "------------------------\n" unless ($quiet);
print "Firewall Update Complete\n" unless ($quiet);

exit(0);

# cute little sub I use everywhere for fancy progress bars. 
sub progress_bar {
	my ( $got, $total, $width, $char ) = @_;
	my $spin = 0;
	$width ||= 25;
	$char  ||= '=';
	my $num_width = length $total;
	local $| = 1;
	if ($spin > 3){
		$spin = 0;
	}
	printf "  -- Inserting new rules %s |%-${width}s| Inserted %${num_width}s rules of %s (%.0f%%)\r",$chars[$spin], $char x (($width-1)*$got/$total). '>', $got, $total, 100*$got/+$total unless ($quiet);
   	$spin++;
}

sub parseopts {
	getopts("vqhf:", \%options);
	if ($options{f}) {
		$firewall = $options{f};
	}
	if ($options{q}) {
		$quiet = 1;
	}
	if ($options{v}) {
		print "Version : $version\n";
		exit(0);
	}
	if ($options{h}) {
		printusage();
		exit(0);
	}
}

sub printusage {

	print "\nUpdate firewall Bad Country options:\n";
	print "-h : This help\n";
	print "-v : Print version info\n";
	print "-q : Quiet mode, disable all standard output. Used for running from CRON.\n";
	print "-f : specify firewall type, can be ipfw, pf, iptables or ipset (ipset is recommended if using iptables)\n\n";

}
