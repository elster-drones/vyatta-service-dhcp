#!/usr/bin/perl -W
#
# Copyright (c) 2019 AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2014, Brocade Comunications Systems, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";

use Getopt::Long;
my $ilfile;
my $olfile;
my $rtinst;
my $lip;
my $lipv6;
my $lmac;
my $pidf;
my $init;
my $config_path;

GetOptions("ilfile=s" => \$ilfile,
	   "olfile=s" => \$olfile,
	   "rtinst=s" => \$rtinst,
	   "lip=s" => \$lip,
	   "lipv6=s" => \$lipv6,
	   "lmac=s" => \$lmac,
	   "pidf=s" => \$pidf,
	   "init=s" => \$init );

sub parse_leases {
    my $ilfile = shift;
    my ($orig_leases, $target_lease);

    local $/=undef;
    open my $leasef, '<', $ilfile
        or die "$0 Error:  Couldn't open file $ilfile:  $!";
    my $leases = <$leasef>;
    close $leasef;

    $orig_leases = $leases;

    if (defined($lip)) {
        $leases =~ s/^|\nlease $lip \{(.|\n)+?\n}//g;
        $target_lease = $lip;
    }

    # delete the specified ipv6 iaaddr lease and any resulting empty ia-na record. 
    if (defined($lipv6)) {
        $leases =~ s/^|\n.+iaaddr $lipv6 \{(.|\n)+?\n.+}//g;
        $leases =~ s/^|\nia-na \".+\" \{\n.+cltt.+;\n}//g;
        $target_lease = $lipv6;
    }

    # delete the mac address and associated lease block
    if (defined($lmac)) {
        my $lmac = lc($lmac);
        $leases =~ s/\n.+hardware ethernet $lmac;((?!{).|\n)+\n}?/\n#HW_MARKER\n}\n/g;
        $leases =~ s/^|\nlease.+ \{((?!{).|\n)+?\n#HW_MARKER\n}//g;
        $target_lease = $lmac;
    }

    return ($orig_leases, $leases, $target_lease);
}

my $error = 0;
my $all_addr = 0;

if (!defined($ilfile) || length($ilfile) == 0) {
	$error = 1;
	print STDERR "$0 Error:  Arg --ilfile not specified, ex: --ilfile=/config/dhcpd.leases\n";
}
if (!defined($olfile) || length($olfile) == 0) {
	print STDERR "$0 Warning:  Arg --olfile not specified, ex: --olfile=/config/dhcpd.leases\n";
}
if (defined($lip) && length($lip)) {
    if ($lip eq 'all') {
	$all_addr = 1
    }
} elsif (defined($lipv6) && length($lipv6)) {
    if ($lipv6 eq 'all') {
        $all_addr = 1
    }
} elsif (defined($lmac) && length($lmac)) {
    if ($lmac eq 'all') {
        $all_addr = 1
    }
} else {
    $error = 1;
    print STDERR "$0 Error:  Arg must specify either --lip, --lmac or --lipv6, ex: --lip=192.168.2.122\n";
}
if (!defined($pidf) || length($pidf) == 0) {
	print STDERR "$0 Warning:  Arg --pidf not specified, ex: --init=/var/run/dhcpd.pid\n";
}
if (!defined($init) || length($init) == 0) {
	print STDERR "$0 Warning:  Arg --init not specified, ex: --init=/opt/vyatta/sbin/dhcpd.init\n";
}

if (-e $ilfile && !$all_addr) {
    my ($leases_orig, $leases, $target) = parse_leases($ilfile);
    if ($leases_orig eq $leases) {
        print STDERR "The lease '$target' was not found.\n";
        $error = 1;
    }
}

exit(1) if ($error == 1);

if (defined($pidf) && length($pidf) && defined($init) && length($init) > 0) {
	if (-f $pidf) {
		system("$init stop $rtinst opmode") == 0 or die "$0 Error:  Unable to stop DHCP server daemon:  $!";
	}
}

if (-e $ilfile) {
	if ($all_addr) {
		unlink($ilfile) or die "$0 Error:  Unable to delete $ilfile:  $!";
	} else {
		my ($leases_orig, $leases, $target) = parse_leases($ilfile);
		if (defined($olfile) && length($olfile) > 0) {
		    open my $outf, '>', $olfile
			or die "$0 Error:  Couldn't open file $olfile:  $!";
			
		    print ${outf} $leases;
		    
		    close $outf;
		} else {
		    print $leases;
		}
	}
}

if ( $rtinst eq "default" ) {
	$config_path = "service";
}
else {
	$config_path = "routing routing-instance $rtinst service";
}
use Vyatta::Config;
my $vcDHCP = new Vyatta::Config();
if (defined($lipv6)) {
	$vcDHCP->setLevel("$config_path dhcpv6-server");
} else {
	$vcDHCP->setLevel("$config_path dhcp-server");
}
if ($vcDHCP->existsOrig('.')) {
	my $disabled = 0;
	my $disabled_val = $vcDHCP->returnOrigValue('disabled');
	if (defined($disabled_val) && $disabled_val eq 'true') {
		$disabled = 1;
		print STDERR "Warning:  DHCP server will be deactivated because 'service dhcp-server disabled' is set to 'true'.\n";
	}

	if ($disabled == 0 && defined($init) && length($init) > 0) {
		system("$init start $rtinst opmode") == 0 or die "$0 Error:  Unable to start DHCP server daemon:  $!";
	}
}

