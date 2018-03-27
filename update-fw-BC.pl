#!/usr/bin/env perl
###################################################################
###################################################################
## update-fw-BC.pl : "Update firewall Bad Countries" This is a perl
## script to easily insert rules into a firewall. The purpose is to
## block all connections from countries selected by the user that
## are known for hacking.
##
## PLEASE READ THE README FILE FOR HOW TO RUN AND REQUIRED
## FW RULES AND LIBRARIES
##
## Written by Sebastian Kai Frost. sebastian.kai.frost@gmail.com

use strict;
use warnings;
use LWP::Simple;
use Getopt::Std;
use Net::Netmask;

# set base variables.
my $version = "v1.5";
my %supportedFW = (
        "ipfw" => 1,
        "ipset" => 1,
        "pf" => 1,
        "iptables" => 1,
        "nftables" => 1
        );
my %options = ();
# where to find the ip_lists.txt file. If running this from CRON this should be a
# full path to the file or it might not work. Can also be set with -i 
my $ipLists = "ip_lists.txt";
my $userList = "";
# Below are the paths for IPFW, PF, iptables and ipset. These are the defaults on
# most modern systems. If yours is in another place. Adjust accordingly.
my $ipfwpath = "/sbin";
my $iptablespath = "/sbin";
my $pfpath = "/sbin";
my $ipsetpath = "/sbin";
my $nftpath = "/usr/sbin/";
# Below are the default tables/chains you're inserting the rules into. You must refrence
# this table in a rule somewhere in your firewall or the script does nothing.
my $ipfwtable = 1;
my $pftable = "badcountries";
my $iptableschain = "badcountries";
my $quiet = 0;
my $firewall = "";
my @ipBlocks;

# Lets parse our command line options.
parseopts();

print "\n*** Update firewall Bad Country $version ***\n\n" unless ($quiet);
print "Updateing firewall - $firewall\n" unless ($quiet);
print "------------------\n" unless ($quiet);


# If there is a user specified IP list, parse that, otherwise use the default ipdeny lists
if ($userList) {
	@ipBlocks = parseUserList();
} else {
	@ipBlocks = parseIPdenyList();
}

# Sort the array into an ordered list. I don't specifically know that net::netmask requires
# the blocks to be adjacent to merge. But lets not risk it.
@ipBlocks = sort(@ipBlocks);

@ipBlocks = aggrigateBlocks(\@ipBlocks);

print "-- Updating firewall...\n" unless ($quiet);

flushOldRules();

insertNewRules(\@ipBlocks);

print "------------------------\n" unless ($quiet);
print "Firewall Update Complete\n" unless ($quiet);

exit(0);

### END OF MAIN SCRIPT SUBS BELOW

sub parseUserList { 
	my $fh;
	my @blocks;
	my $row;
	my $ip;

	print "-- Using user supplied IP list.\n";
	open($fh, '<:encoding(UTF-8)', $userList) or die "Could not open file '$userList' $!";
	while ($row = <$fh>) {
		chomp $row;
		$ip = (split("/", $row))[0];
		verifyIP($ip);
		push @blocks, Net::Netmask->new($row);
	}
	print "  -- Done\n" unless ($quiet);
	return @blocks;
}

sub  parseIPdenyList {

	my $listsFH;
	my $row;
	my $content;
	my @tempblocks;
	my @blocks;
	my $ip;

	print "-- Grabbing IP Lists and extracting IP blocks...\n" unless ($quiet);

        open($listsFH, '<:encoding(UTF-8)', $ipLists) or die "Could not open file '$ipLists' $!";

        # run through each of the URLs of IP blocks and grab them, then shove each IP block in
        # an array.
        while ($row = <$listsFH>) {
                chomp $row;
                $content = get($row) or die 'Unable to get page';
                @tempblocks = split(/\n/, $content);
                foreach (@tempblocks) {
			$ip = (split("/", $_))[0];
			verifyIP($ip);
                        push @blocks, Net::Netmask->new($_);
                }
        }
        close $listsFH;
	print "  -- Done\n" unless ($quiet);
	return @blocks
}

sub aggrigateBlocks {
	my @blocks = @{$_[0]};
	my $beforecount;
	my $aftercount;
	
	# count how many networks we have to start with so we can compare with after and feel good about
	# our efficiency.
	$beforecount = @blocks;

	print "-- Aggregating networks...\n" unless ($quiet);
	# aggregate the networks using cidrs2cidrs
	@blocks = cidrs2cidrs(@blocks);
	# count how many we have now. Look how shiny Net::Netmask is!
	$aftercount = @blocks;
	print "  -- Done\n" unless ($quiet);
	print "  -- Networks before/after aggregation : $beforecount/$aftercount\n" unless ($quiet);
	return @blocks;
}

sub flushOldRules {

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
}


sub insertNewRules {
	my @blocks = @{$_[0]};
	my $count;
	my $fh;
	my $ip;
	my $mask;
	my $spin = 0; 
	my $blockCount = @blocks;
	
	# go through and put in the new rules. Lets give the user a nice progress bar to go with it
	# as this can take a long time. Also a spinning wheel so if they manage to firewall themselves
	# out they will see this pretty quickly.
	$count = 1;
	if ($firewall eq "nftables") {
		open ($fh, ">", "/tmp/nft.rules");
		print $fh "add element filter country_block {";
	}
	foreach (@ipBlocks) {
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
		if ($spin > 3) {
                        $spin = 0;
                }
		progress_bar( $count, $blockCount, 25, '=', $spin );
		$spin++;
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

}	

# cute little sub I use everywhere for fancy progress bars.
sub progress_bar {
	my ( $got, $total, $width, $char, $spin ) = @_;
	my @chars = qw(| / - \ );
	$width ||= 25;
	$char  ||= '=';
	my $num_width = length $total;
	local $| = 1;
	printf "  -- Inserting new rules %s |%-${width}s| Inserted %${num_width}s rules of %s (%.0f%%)\r",$chars[$spin], $char x (($width-1)*$got/$total). '>', $got, $total, 100*$got/+$total unless ($quiet);
}

sub verifyIP {
	my $ipaddr = shift;

	if( $ipaddr =~ m/^(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)$/ ) {
    		if($1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255) {
			# all valid, do nothing
		} else {
			print("--> IP address $ipaddr : has an octect out of range and is invalid!  All octets must contain a number between 0 and 255 \n");
			exit(0);
		}
	} else {
    		print("--> IP Address $ipaddr : NOT IN VALID FORMAT! Please fix and re-run script. \n");
		exit(0);
	}
}



# Sub to parse command line options
sub parseopts {
	my $key;
	
	getopts("vqhi:l:f:", \%options);
	if ($options{f}) {
		$firewall = $options{f};
	}
	if ($options{l}) {
		$userList = $options{l};
	}
	if ($options{i}) {
		$ipLists = $options{i};
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
	unless ($firewall) {
                print "\n--> No firewall specified, please specify your firewall package\n";
                printusage();
                exit(1);
        }

        unless(exists($supportedFW{$firewall})) {
                print "\n--> Unsupported firewall type \"$firewall\" specified, please specify one of: \n";
		for $key (keys %supportedFW) {
			print " - $key\n";
		}
                printusage();
                exit(1);
        }
}

# print the usage summary for the script
sub printusage {

	print "\nUpdate firewall Bad Country options:\n";
	print "-f : (required) specify firewall type, can be ipfw, pf, iptables, nftables or ipset (ipset is recommended if using iptables)\n";
	print "-l : (optional) specify an IP lists file to import your own IP list. See README for format\n";
	print "-i : (optional) optional full path to your ip_lists.txt file that defines the URLs to pull IPs from, useful if you run this from cron\n";
	print "-q : Quiet mode, disable all standard output. Used for running from CRON.\n";
	print "-v : Print version info\n";
	print "-h : This help\n\n";

}
### END OF PROGRAM ###
