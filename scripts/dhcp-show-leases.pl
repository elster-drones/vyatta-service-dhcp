#!/usr/bin/perl
#
# Copyright (c) 2019-2020 AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2013-2015, Brocade Comunications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;
use Getopt::Long;
use NetAddr::IP;
use URI::Encode qw(uri_decode);
use JSON qw( encode_json );
use POSIX qw(strftime);
use lib '/opt/vyatta/share/perl5';
use Vyatta::Config;
use Vyatta::DHCPServerOpMode;

my $lease_filename;

sub get_leases {
    my $routing_inst = shift;
    my $required_pool = shift;
    my $want_expired = shift;

    my %leases = ();      # hash table for all leases associated with a pool.
    my %leases_hash = (); # hash table for all leases in dhcpd.leases
    my $cur;

    open( my $leases, '<', $lease_filename )
      or die "Can't open $lease_filename: $!\n";

    while (<$leases>) {
        my $line = $_;
        if ( $line =~ /lease\s(\d+\.\d+\.\d+\.\d+)/ ) {
            $cur = { ip => $1 };
        }
        next unless $cur;

        if ( $line =~ /starts epoch\s(\d*);\s+/ ) {
            $cur->{start} = strftime ( "%Y/%m/%d %X", localtime($1));
        } elsif ( $line =~ /starts\s\d\s(\d+\/\d+\/\d+\s\d+:\d+:\d+)\;/ ) {
            $cur->{start} = $1;
        }
        if ( $line =~ /ends epoch\s(\d*);\s+/ ) {
            $cur->{end} = strftime ( "%Y/%m/%d %X", localtime($1));
        } elsif ( $line =~ /ends\s\d\s(\d+\/\d+\/\d+\s\d+:\d+:\d+)\;/ ) {
            $cur->{end} = $1;
        }
        if ($line =~ /shared-network:\s(.*)/) {
            $cur->{pool} = $1;
        }
        if ( $line =~ /hardware\sethernet\s(.*?)\;/ ) {
            $cur->{mac} = $1;
        }
        if ( $line =~ /client-hostname\s"(.*?)"\;/ ) {
            $cur->{name} = $1;
        }
        if ( $line =~ /^\s+binding\sstate\s(.*?)\;/ ) {
            $cur->{state} = $1;
        }
        if ( $line =~ /^}/ ) {
            $leases_hash{$cur->{ip}} =  $cur;
            $cur = undef;
        }
    }

    # Match leases against the various pool ranges
    my $pool_info = Vyatta::DHCPServerOpMode::get_pool_info($routing_inst);
    while ( my ($my_ip, $my_lease ) = each(%leases_hash) ) {
        # Ignore expired/non-expired leases as requested
        if (defined($want_expired)) {
            next if ( $my_lease->{state} eq 'active' );
        } else {
            next unless ( $my_lease->{state} eq 'active' );
        }

        POOL: for my $pool (keys %{$pool_info}) {
            # Ignore this pool if it is not of interest
            next if defined($required_pool) and ($pool ne $required_pool);

            if ($my_lease->{pool} eq $pool) {
                $leases{$my_lease->{ip}} = $my_lease;
                last POOL;
            }
        } # end of POOL
    } # end of while

    return %leases;
}

sub convertto_ietfdate {
    my ($time) = @_;
	
    $time =~ s/\//-/g;
    $time =~ s/\s/T/;

    return $time;
}


# Eexpiration time retieved from leases file does not
# include a timezone.
# Add the timezone to make it ISO8601 compliant, and
# fit in ietf-yang-types date-and-time definition.
sub append_timezone {
    my ($time) = @_;
    my $tz = strftime( "%z", localtime() );

    #timezone needs conversion from [+-]hhmm to [+-]hh:mm
    $tz =~ s/(\d{2})(\d{2})/$1:$2/;

    return $time . $tz;
}

# main
my ( $rtinst, $expired, $pool, $netconf );

GetOptions(
    "rtinst=s"     => \$rtinst,
    "expired"      => \$expired,
    "pool=s"       => \$pool,
    "netconf"      => \$netconf,
);

# for retrieving dhcp server leases via Netconfi API
my %output;
my @leases_out;

# need to find out non-default routing-instance name through ENV CONFIGD_PATH
if ( ( defined ($netconf) ) &&
     ( defined ($rtinst) )  &&
     ( $rtinst eq "all" ) ) {
    my @elems = map {uri_decode($_)} split("/", $ENV{"CONFIGD_PATH"});
    $rtinst = $elems[3] if ( defined ($elems[3]) );
}

# DHCP Server is not running 
my $dhcpv4 = `ps -ef | grep dhcpd | grep "$rtinst" | grep -v "grep" | grep -v "dhcpdv6"`;
if ($dhcpv4 eq "") {
    if ( defined ($netconf) ) {
        print encode_json( \%output );
    } else {
        print "No DHCP server running\n";
    }
    exit 0;
}

$lease_filename = "/config/dhcpd/dhcpd_vrf_$rtinst.leases";

my %leases = get_leases($rtinst, $pool, $expired);

if ( defined ($netconf) ) {
    while ( my ( $my_ip, $my_lease ) = each ( %leases ) ) {
        my %lease;

        $lease{"ip-address"} = $my_ip;
        $lease{"hw-address"} = $my_lease->{mac};
        $lease{"pool"} = $my_lease->{pool};
        $lease{"host"} = $my_lease->{name};

	if ( defined ( $my_lease->{end} ) ) {
            my $expiration_time = convertto_ietfdate ( $my_lease->{end} );
            $lease{"lease-expiration"} = append_timezone( $expiration_time );
        }

        push @leases_out, \%lease;
    }

    $output{"leases"} = \@leases_out;

    print encode_json( \%output );
    exit 0;
} else {
    my $num_leases = keys %leases;

    if ($num_leases == 0) {
        printf "There are no DHCP leases.\n";
        exit 0;
    } elsif ($num_leases == 1) {
        printf "There is one DHCP lease:\n";
    } else {
        printf "There are $num_leases DHCP leases:\n";
    }

    my $fmt = "%-16s %-18s %-20s %-10s %s\n";
    printf $fmt, "IP address", "Hardware Address", "Lease Expiration",
	  "Pool", ( defined($expired) ? "" : "Name" );

    printf $fmt, "-----------", "-----------------",
    	"-------------------", "---------",
    	( defined($expired) ? "" : "-------" );

    for my $ip ( sort(keys %leases) ) {
        my $lease = $leases{$ip};

        next if ( defined($expired) && !defined($lease->{mac}) );

        printf $fmt, $lease->{ip},
          ( defined($lease->{mac}) ? $lease->{mac} : "" ),
          ( defined($lease->{end}) ? $lease->{end} : "" ),
          ( defined($lease->{pool}) ? $lease->{pool} : "" ),
          ( defined($lease->{name}) ? $lease->{name} : "" );
    }
}
