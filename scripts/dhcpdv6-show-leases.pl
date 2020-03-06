#!/usr/bin/perl

# Module: dhcpdv6-leases.pl
#
# **** License ****
# Copyright (c) 2019-2020 AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2014, Brocade Comunications Systems, Inc.
# All Rights Reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: Bob Gilligan
# Date: April 2010
# Description: Script to display DHCPv6 server leases in a user-friendly form
#
# **** End License ****

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";

use Getopt::Long;
use Time::Local;
use NetAddr::IP;
use Vyatta::Config;
use Vyatta::DHCPv6Duid;


# Globals
my $lease_filename;
my $debug_flag = 0;
my $rtinst;
my $expired = 0;
my $detailed = 0;

sub log_msg {
    my $message = shift;

    print "DEBUG: $message" if $debug_flag;
}

GetOptions(
    "rtinst=s"  =>  \$rtinst,
    "expired"   => \$expired,
    "detailed"   => \$detailed,
    "debug"     => \$debug_flag,
    );

#
# Main section.
#
my @lines=();

if ( !defined $rtinst ) {
    $rtinst = "default";
}

my $dhcpv6 = `ps -aef | grep "dhcpd" | grep " -6" | grep "$rtinst" | grep -v "grep"`;
if ( $dhcpv6 eq "" ) {
    printf("DHCPv6 Server is not running\n");
    exit 0;
}

$lease_filename = "/var/log/dhcpdv6/dhcpdv6_vrf_$rtinst.leases";
open my $leasef, '<', $lease_filename
    or die "DHCPv6 server is not running\n";

@lines = <$leasef>;
close($leasef);
chomp @lines;

my $level = 0;
my $prev_level = 0;
my $s1;
my $s2;
my $ia_na;
my $ia_pd;
my $ia_ta;
my $iaaddr;
my $iaprefix;
my $duid;
my $iaid;
my $exp_time;
my $binding_state;
my $cltt;
my %addr_ghash = ();
my %addr_ta_ghash = ();
my %prefix_ghash = ();

# Sort by IPv6 address. $a and $b are IPv6 address strings which may
# or may not have a "/bits" at end.
#
sub by_addr {
    my $ipa = new NetAddr::IP($a);
    my $ipb = new NetAddr::IP($b);
    $ipa <=> $ipb;
}

sub time_string {
    my ($time) = (@_);
    if ($time == 0) {
	return "never";
    }
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	localtime($time);
    my $ret = sprintf("%d/%d/%d %02d:%02d:%02d",
		      $year+1900, $mon + 1, $mday, $hour, $min, $sec);
    return $ret;
}

#
# print_leases
#   %ghash - hash table indexed by address
#   $order - sort function
#   $width - address/prefix field width
#
sub print_leases {
    my ($param, $order, $width, $addr_or_pfx, $detail) = @_;
    my %ghash = %$param;

    foreach my $key (sort $order keys %ghash) {
	my $entry = $ghash{$key};
	my ($iaid, $duid, $cltt, $time, $state) = @$entry;
	my $time_string = time_string($time);
	my $duid_short;
	my $duid_id;

	#
	# Anything derived from the DUID may be undefined if we failed
	# to parse the DUID string in the leases file
	#
	if (!defined($iaid)) {
	    $iaid = "-";
	}
	if (!defined($duid)) {
	    $duid_short = "-";
	    $duid_id = "-";
	} else {
	    $duid_short = sprintf("%s", $duid->print(format => 'short'));
	    $duid_id = sprintf("%s", $duid->print(format => 'id'));
	}

	if ($detail) {
	    printf("Client IPv6 %s: %s\n", $addr_or_pfx, $key);
	    printf("  Client IA-ID: %s\n", $iaid);
	    printf("  Client DUID:  %s\n", $duid_short);
	    printf("  State:        %s\n", $state);
	    printf("  Client Id:    %s\n", $duid_id);
	    printf("  Expires:      %s\n", $time_string);
	    printf("  Expires in:   %d seconds\n", $time);
	    printf("  Client LTT:   %s\n", time_string($cltt));
	    printf("\n");
	} else {
	    printf ("%-${width}s %-8s %-19s %s\n", $key, $iaid, $time_string, $state);
	}
    }
}

# Parse the leases file into a hash keyed by IPv6 addr.
foreach my $line (@lines) {
    #
    # Undef the local variables when $level changed from 0
    #
    if ($prev_level != 0 && $level == 0) {
	log_msg("Resetting loop variables\n");
	undef $ia_na;
	undef $ia_pd;
	undef $ia_ta;
	undef $iaaddr;
	undef $iaprefix;
	undef $duid;
	undef $iaid;
	undef $exp_time;
	undef $binding_state;
	undef $cltt;
    }
    $prev_level = $level;

    log_msg("Line: $line\n");

    if ($line =~ /^#/) {
	# Comment. Ignore
    } elsif ($line =~ /^server-duid .*/) {
	my $s3;
	($s1, $s2, $s3) = split(' ', $line);

	# Remove quotes and semi-colon at start and end
	$s2 =~ s/;$//;
	$s2 =~ s/(^")|("$)//g;

	my $server_duid = Vyatta::DHCPv6Duid->new($s2);
	if (defined($server_duid)) {
	    log_msg("server duid: " . $server_duid->print() .  "\n");
	}
    } elsif ($line =~ /^ia-na .*\{/) {
	if ($level != 0) {
	    log_msg("Found ia-na at level $level\n");
	    last;
	}
	log_msg("setting ia_na\n");
	($s1, $ia_na, $s2) = split(' ', $line);

	# Remove quotes and semi-colon at start and end
	$ia_na =~ s/;$//;
	$ia_na =~ s/(^")|("$)//g;

	#
	# The ia-na is a mixed string of octal and ascii.  It
	# comprises a four octet IAID followed by a DUID.
	#
	$ia_na =~ s/^(\\[0-9]{3}){4}//;  # Remove first 4 octal chars
	$iaid = Vyatta::DHCPv6Duid::octstohexs($&);
	if (length($iaid) != 8) {
	    # Invalid iaid, so undef it
	    undef $iaid;
	} else {
	    log_msg("iaid: " . $iaid . "\n");
	}

	$duid = Vyatta::DHCPv6Duid->new($ia_na);
	if (defined($duid)) {
	    log_msg("duid: " . $duid->print() .  "\n");
	}

	$level++;
    } elsif ($line =~ /^ia-pd .*\{/) {
	if ($level != 0) {
	    log_msg("Found ia-pd at level $level\n");
	    last;
	}
	log_msg("setting ia_pd\n");
	($s1, $ia_pd, $s2) = split(' ', $line);

	# Remove quotes and semi-colon at start and end
	$ia_pd =~ s/;$//;
	$ia_pd =~ s/(^")|("$)//g;

	#
	# The ia-pd is a mixed string of octal and ascii.  It
	# comprises a four octet IAID followed by a DUID.
	#
	$ia_pd =~ s/^(\\[0-9]{3}){4}//;  # Remove first 4 octal chars
	$iaid = Vyatta::DHCPv6Duid::octstohexs($&);
	if (length($iaid) != 8) {
	    # Invalid iaid, so undef it
	    undef $iaid;
	} else {
	    log_msg("iaid: " . $iaid . "\n");
	}

	$duid = Vyatta::DHCPv6Duid->new($ia_pd);
	if (defined($duid)) {
	    log_msg("duid: " . $duid->print() .  "\n");
	}

	$level++;
    } elsif ($line =~ /^ia-ta .*\{/) {
        if ($level != 0) {
            log_msg("Found ia-ta at level $level\n");
            last;
        }
        log_msg("setting ia_ta\n");
        ($s1, $ia_ta, $s2) = split(' ', $line);

        # Remove quotes at start and end and remove "," and "-"
        $ia_ta =~ s/(^")|("$)//g;
        $ia_ta =~ s/[,-]//g;

        #
        # The ia-ta is a mixed string of octal and ascii.  It
        # comprises a four octet IAID followed by a DUID.
        #
        $ia_ta =~ s/^(\\[0-9]{3}){4}//;  # Remove first 4 octal chars
        $iaid = Vyatta::DHCPv6Duid::octstohexs($&);
        if (length($iaid) != 8) {
            # Invalid iaid, so undef it
            undef $iaid;
        } else {
            log_msg("iaid: " . $iaid . "\n");
        }

        $duid = Vyatta::DHCPv6Duid->new($ia_ta);
        if (defined($duid)) {
            log_msg("duid: " . $duid->print() .  "\n");
        }

        $level++;
    } elsif ($line =~ /^.*iaaddr .*\{/) {
	if ($level != 1) {
	    log_msg("Found iaaddr at level $level\n");
	    last;
	}
	($s1, $iaaddr, $s2) = split(' ', $line);
	log_msg("Setting iaaddr to $iaaddr.\n");
	log_msg("s1 $s1 s2 $s2\n");
	$level++;
    } elsif ($line =~ /^.*iaprefix .*\{/) {
	if ($level != 1) {
	    log_msg("Found iaprefix at level $level\n");
	    last;
	}
	($s1, $iaprefix, $s2) = split(' ', $line);
	log_msg("Setting iaprefix to $iaprefix.\n");
	log_msg("s1 $s1 s2 $s2\n");
	$level++;
    } elsif ($line =~ /^.*cltt epoch/) {
	my $epoch;
	($s1, $s2, $epoch) = split(' ', $line);
	$epoch =~ s/;//;
	$cltt = int($epoch);
    } elsif ($line =~ /^.*cltt/) {
	#
	# Clients last transaction time.  Only record the latest entry
	# for a given binding.
	#
	my $date;
	my $time;
	if ($level != 1) {
	    log_msg("Found cltt at level $level\n");
	    last;
	}
	($s1, $s2, $date, $time) = split(' ', $line);
	$time =~ s/;//;
	my ($year, $month, $day) = split(/\//, $date);
	my ($hour, $min, $sec) = split(/:/, $time);
	$cltt = timelocal($sec, $min, $hour, $day, $month - 1, $year);
    } elsif ($line =~ /^.*ends never/) {
	log_msg("Setting expiry time to 0\n");
	$exp_time = 0;
    } elsif ($line =~ /^.*ends epoch /) {
	my $epoch;
	($s1, $s2, $epoch) = split(' ', $line);
	$epoch =~ s/;//;
	$exp_time = int($epoch);
    } elsif ($line =~ /^.*ends /) {
	my $date;
	my $time;
	if ($level != 2) {
	    log_msg("Found ends at level $level\n");
	    last;
	}
	log_msg("Setting expiry time\n");
	($s1, $s2, $date, $time) = split(' ', $line);
	$time =~ s/;//;
	my ($year, $month, $day) = split(/\//, $date);
	my ($hour, $min, $sec) = split(/:/, $time);
	$exp_time = timelocal($sec, $min, $hour, $day, $month - 1, $year);
    } elsif ($line =~ /^.*binding state /) {
	if ($level != 2) {
	    log_msg("Found binding state at level $level\n");
	    last;
	}
	log_msg("Setting binding state\n");
	($s1, $s2, $binding_state) = split(' ', $line);
	$binding_state =~ s/;//;
    } elsif ($line =~ /^.*\{/) {
	log_msg("Unknown clause: $line\n");
	$level++;
    } elsif ($line =~ /\}/) {
	$level--;
	if ($level == 0) {
	    #
	    # First check we have a minimum state
	    #
	    if (defined($ia_na)) {
		if (!defined($iaaddr)) {
		    log_msg("iaaddr not defined\n");
		    next;
		}
	    } elsif (defined($ia_pd)) {
		if (!defined($iaprefix)) {
		    log_msg("iaprefix not defined\n");
		    next;
		}
	    } elsif (defined($ia_ta)) {
		if (!defined($iaaddr)) {
		    log_msg("iaaddr not defined\n");
		    next;
		}
	    } else {
		log_msg("None ia_na, or ia_ta or ia_pd defined\n");
		next;
	    }

	    if (!defined($exp_time)) {
		log_msg("Expiry time not defined\n");
		next;
	    }

	    if (defined($ia_na)) {
		$iaaddr =~ tr/A-Z/a-z/;  # lowercase

		if (($expired && $binding_state =~ /.*(expired|abandoned).*/i) ||
		    ($expired == 0 && $binding_state !~ /.*(expired|abandoned).*/i)) {
		    #
		    # Check to see if we have already added an entry
		    # for this address
		    #
		    my $entry;
		    if ($entry = $addr_ghash{$iaaddr}) {
			my ($e_iaid, $e_duid, $e_cltt, $e_time, $e_state) = @$entry;
			if ($e_cltt > $cltt) {
			    # Existing entry has a later "last seen" date
			    next;
			}
		    }
		    log_msg("Setting addr_ghash entry for $iaaddr to $exp_time\n");
		    my @array = ($iaid, $duid, $cltt, $exp_time, $binding_state);
		    $addr_ghash{$iaaddr} = \@array;
		}
            } elsif (defined($ia_ta)) {
                $iaaddr =~ tr/A-Z/a-z/;  # lowercase

                if (($expired && $binding_state =~ /.*(expired|abandoned).*/i) ||
                    ($expired == 0 && $binding_state !~ /.*(expired|abandoned).*/i)) {
                    #
                    # Check to see if we have already added an entry
                    # for this address
                    #
                    my $entry;
                    if ($entry = $addr_ta_ghash{$iaaddr}) {
                        my ($e_iaid, $e_duid, $e_cltt, $e_time, $e_state) = @$entry;
                        if ($e_cltt > $cltt) {
                            # Existing entry has a later "last seen" date
                            next;
                        }
                    }
                    log_msg("Setting addr_ta_ghash entry for $iaaddr to $exp_time\n");
                    my @array = ($iaid, $duid, $cltt, $exp_time, $binding_state);
                    $addr_ta_ghash{$iaaddr} = \@array;
                }
	    } elsif (defined($ia_pd)) {
		$iaprefix =~ tr/A-Z/a-z/;  # lowercase

		if (($expired && $binding_state =~ /.*(expired|abandoned).*/i) ||
		    ($expired == 0 && $binding_state !~ /.*(expired|abandoned).*/i)) {
		    #
		    # First check to see if we have already added an
		    # entry for this address
		    #
		    my $entry;
		    if ($entry = $prefix_ghash{$iaprefix}) {
			my ($e_iaid, $e_duid, $e_cltt, $e_time, $e_state) = @$entry;
			if ($e_cltt > $cltt) {
			    # Existing entry has a later "last seen" date
			    next;
			}
		    }
		    log_msg("Setting prefix_ghash entry for $iaprefix to $exp_time\n");
		    my @array = ($iaid, $duid, $cltt, $exp_time, $binding_state);
		    $prefix_ghash{$iaprefix} = \@array;
		}
	    }
 	}
    }
}

# Display the leases...

my $num_entries = scalar(keys %addr_ghash);
if ($num_entries == 0) {
    printf("There are no DHCPv6 ia_na address leases\n");
} elsif ($num_entries == 1) {
    printf("There is one DHCPv6 ia_na address lease\n");
} else {
    printf("There are $num_entries DHCPv6 ia_na address leases\n");
}

my $num_ta_entries = scalar(keys %addr_ta_ghash);
if ($num_ta_entries == 0) {
    printf("There are no DHCPv6 ia_ta address leases\n");
} elsif ($num_ta_entries == 1) {
    printf("There is one DHCPv6 ia_ta address lease\n");
} else {
    printf("There are $num_ta_entries DHCPv6 ia_ta address leases\n");
}

my $num_prefixes = scalar(keys %prefix_ghash);
if ($num_prefixes == 0) {
    printf(" and no DHCPv6 prefix leases.\n");
} elsif ($num_prefixes == 1) {
    printf(" and one DHCPv6 prefix lease.\n");
} else {
    printf(" and $num_prefixes DHCPv6 prefix leases.\n");
}

if ($num_entries == 0 && $num_ta_entries == 0 && $num_prefixes == 0) {
    exit 0;
}

if ($num_entries != 0) {
    printf("\n");
    if (!$detailed) {
	printf("IPv6 ia_na Address                      IAID     Expiration          State\n");
	printf("--------------------------------------- -------- ------------------- ------\n");
    }
    print_leases(\%addr_ghash, \&by_addr, 39, "Address", $detailed);
}

if ($num_ta_entries != 0) {
    printf("\n");
    if (!$detailed) {
        printf("IPv6 ia_ta Address                      IAID     Expiration          State\n");
        printf("--------------------------------------- -------- ------------------- ------\n");
    }
    print_leases(\%addr_ta_ghash, \&by_addr, 39, "Address", $detailed);
}

if ($num_prefixes != 0) {
    printf("\n");
    if (!$detailed) {
	printf("IPv6 Prefix                                 IAID     Expiration          State\n");
	printf("------------------------------------------- -------- ------------------- ------\n");
    }
    print_leases(\%prefix_ghash, \&by_addr, 43, "Prefix", $detailed);
}
