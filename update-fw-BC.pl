#!/usr/bin/env perl
###################################################################
###################################################################
## update-fw-BC.pl : "Update firewall Bad Countries" This is a perl
## script to easily insert rules into a firewall. The purpose is to
## block all connections from countries selected by the user that
## are known for hacking.
##
## It takes one file as input in the CWD dir: "ip_lists.txt" which
## is a file containing links to files on ipdeny.com per line.
## These files are aggregated lists of netblocks known to be in
## that country.
##
## For each link it grabs the list, ingests it, sorts the netblocks
## and then aggregates them again where posible using Net::Netmask.
## It then inserts these IPs into a firewall.
##
## Currently supported are : IPFW, PF, IPTABLES, IPTABLES+IPSET
##
## It is up to the user to have a rule that points to the table
## in your firewall. In IPFW it's a number. in PF a name.
##
## PLEASE READ THE README FILE FOR HOW TO RUN AND REQUIRED
## FW RULES AND LIBRARIES
##
## v1.0 : Basic ipfw support
## v1.1 : Added pf and iptables support
## v1.2 : Added ipset support
## v1.3 : Added nftables support
##
## Written by Sebastian Kai Frost. sebastian.kai.frost@gmail.com
##

use strict;
use warnings;
use LWP::Simple;
use Getopt::Std;
use Net::Netmask;

# set base variables.
my $version = "v1.3";
# where to find the ip_lists.txt file. If running this from CRON this should be a
# full path to the file or it might not work.
my $ipLists = "ip_lists.txt";
# Below are the paths for IPFW, PF, iptables and ipset. These are the defaults on
# modern systems. If yours is in another place. Adjust accordingly.
my $ipfwpath = "/sbin";
my $iptablespath = "/sbin";
my $pfpath = "/sbin";
my $ipsetpath = "/sbin";
my $nftpath = "/usr/sbin/";
# below is the tables/chain you're inserting the rules into. You must refrence
# this table in a rule somewhere in yoyr firewall or the script does nothing.
my $ipfwtable = 1;
my %supportedFW = (
	"ipfw" => 1,
       	"ipset" => 1,
       	"pf" => 1,
       	"iptables" => 1,
       	"nftables" => 1
	);
my $pftable = "badcountries";
my $iptableschain = "badcountries";
my $quiet = 0;
my $firewall = "";
my $listsFH;
my @chars = qw(| / - \ );
my %options = ();
my $count;
my $row;
my $content;
my $beforecount;
my $aftercount;
my @tempblocks;
my @ipblocks;
my @ipblockOBJ;
my $fh;
my $ip;
my $mask;

# Lets parse our command line options.
parseopts();

print "\n*** Update firewall Bad Country $version ***\n\n" unless ($quiet);

unless ($firewall) {
	print "No firewall specified, please specify your firewall package\n\n" unless ($quiet);
	printusage();
	exit(1);
}

unless(exists($supportedFW{$firewall})) {
	print "Unsupported firewall type \"$firewall\" specified, please specify one of: ";
	print "$_ " for keys %supportedFW;
	print "\n";
	printusage();
	exit(1);
}

print "Updateing firewall - $firewall\n" unless ($quiet);
print "------------------\n" unless ($quiet);

print "-- Grabbing IP Lists and extracting IP blocks...\n" unless ($quiet);

open($listsFH, '<:encoding(UTF-8)', $ipLists) or die "Could not open file '$ipLists' $!";

# run through each of the URLs of IP blocks and grab them, then shove each IP block in
# an array.
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

# sort the array into an ordered list. I don't specifically know that net::netmask requires
# the blocks to be adjacent to merge. But lets not risk it.
@ipblocks = sort(@ipblocks);

# count how many networks we have to start with so we can compare with after and feel good about
# our efficiency.
$beforecount = @ipblocks;

# create an array of Net::Netmask objects for it to work with.
foreach (@ipblocks) {
	push @ipblockOBJ, Net::Netmask->new($_);
}

print "-- Aggregating networks...\n" unless ($quiet);
# aggregate the networks using cidrs2cidrs
@ipblockOBJ = cidrs2cidrs(@ipblockOBJ);
# count how many we have now. Look how shiny Net::Netmask is!
$aftercount = @ipblockOBJ;
print "  -- Done\n" unless ($quiet);
print "  -- Networks before/after aggregation : $beforecount/$aftercount\n" unless ($quiet);

# lets finally go update our firewall.
print "-- Updating firewall...\n" unless ($quiet);

# flush out the old list.
print "  -- Flushing old rules...\n" unless ($quiet);
if ($firewall eq "ipfw") {
	system "$ipfwpath/ipfw table $ipfwtable flush";
} elsif ($firewall eq "pf") {
	system "$pfpath/pfctl -q -t $pftable -T flush";
} elsif ($firewall eq "iptables") {
	system "$iptablespath/iptables -F $iptableschain";
} elsif ($firewall eq "ipset") {
	system "$ipsetpath/ipset flush $iptableschain";
} elsif ($firewall eq "nftables") {
	system "$nftpath/nft flush set filter country_block";
} else {
	print "Unknown firewall type\n";
	exit(1);
}
print "  -- Done\n" unless ($quiet);

# go through and put in the new rules. Lets give the user a nice progress bar to go with it
# as this can take a long time. Also a spinning wheel so if they manage to firewall themselves
# out they will see this pretty quickly.
$count = 1;
if ($firewall eq "nftables") {
	open ($fh, ">", "/tmp/nft.rules");
	print $fh "add element filter country_block {";
}
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
	} elsif ($firewall eq "nftables") {
		print $fh "$ip/$mask, ";
	} else {
		print "Unknown firewall type\n";
		exit(1);
	}
	progress_bar( $count, $aftercount, 25, '=' );
	$count++;
}
if ($firewall eq "nftables") {
	print $fh "}\n";
	close $fh;
	system "$nftpath/nft -f /tmp/nft.rules";
	unlink "/tmp/nft.rules";
}
print "\n" unless ($quiet);
print "  -- Done\n" unless ($quiet);
print "------------------------\n" unless ($quiet);
print "Firewall Update Complete\n" unless ($quiet);

exit(0);

### END OF MAIN SCRIPT SUBS BELOW

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

# Sub to parse command line options
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

# print the usage summary for the script
sub printusage {

	print "\nUpdate firewall Bad Country options:\n";
	print "-h : This help\n";
	print "-v : Print version info\n";
	print "-q : Quiet mode, disable all standard output. Used for running from CRON.\n";
	print "-f : specify firewall type, can be ipfw, pf, iptables, nftables or ipset (ipset is recommended if using iptables)\n\n";

}

### END OF PROGRAM ###
