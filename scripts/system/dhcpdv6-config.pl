#!/usr/bin/perl

# Module: dhcpdv6-config.pl
#
# **** License ****
# Copyright (c) 2019-2020 AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: Bob Gilligan
# Date: March 2010
# Description: Script to setup DHCPv6 server
#
# **** End License ****

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";

use Getopt::Long;
use Vyatta::Config;
use NetAddr::IP;
use HTML::Entities;
use Vyatta::Misc;
use Vyatta::DHCPv6Duid;

# Globals
my $config_dir = '/opt/vyatta/etc/dhcpdv6/';
my $config_filename;
my $rtinst;          # Indicates which routing-instance we are running on.
my $op_mode_flag;    # Indicates we are running in op mode if set.
my $config_prefix;
my $config_filehandle;
my $error = 0;
my @names;

GetOptions(
    "rtinst=s"      => \$rtinst,
    "op_mode_flag"  => \$op_mode_flag,
);

mkdir $config_dir;

if ( !defined $rtinst ) {
    $rtinst = "default";
}
if ( $rtinst eq "default" ) {
    $config_prefix = "service";
}
else {
    $config_prefix = "routing routing-instance $rtinst service";
}

$config_filename = $config_dir . "dhcpdv6_vrf_$rtinst.conf";

# Use proper Vyatta PERL APIs based on op_mode_flag
my $returnValues = ( $op_mode_flag ? "returnOrigValues" : "returnValues" );
my $returnValue  = ( $op_mode_flag ? "returnOrigValue"  : "returnValue" );
my $listNodes    = ( $op_mode_flag ? "listOrigNodes"    : "listNodes" );
my $exists       = ( $op_mode_flag ? "existsOrig"       : "exists" );

#
# Functions that are used in writing out dhcpdv6.conf
#
my @temp_list = ();

sub write_cf {
    my ($string) = @_;
    printf( $config_filehandle "$string" );
}

sub write_cf_nl {
    my ($string) = @_;
    printf( $config_filehandle "$string;\n" );
}

#
# A simple list is written out to the config file with each item
# separated by commas.
#
sub write_list {
    my ($string) = @_;

    my $num_items = scalar(@temp_list);
    if ( $num_items > 0 ) {
        printf( $config_filehandle "$string " );
        my $item_count = 0;
        foreach my $item (@temp_list) {
            if ( $item_count > 0 ) {
                printf( $config_filehandle ", " );
            }
            printf( $config_filehandle "$item" );
            $item_count++;
        }
        printf( $config_filehandle ";\n" );
    }
    @temp_list = ();
}

# A domain list differs from a simple list in that each
# element must be enclosed in double-quotes, then
# separated by commas.
#
sub write_domain_list {
    my ($string) = @_;

    my $num_items = scalar(@temp_list);
    if ( $num_items > 0 ) {
        printf( $config_filehandle "$string " );
        my $item_count = 0;
        foreach my $item (@temp_list) {
            if ( $item_count > 0 ) {
                printf( $config_filehandle ", " );
            }
            printf( $config_filehandle "\"$item\"" );
            $item_count++;
        }
        printf( $config_filehandle ";\n" );
    }
    @temp_list = ();
}

sub push_list {
    my ($string) = @_;
    push( @temp_list, $string );
}

sub write_lease_limits {
    my $indent = shift;
    my $vc     = shift;

    if ( $vc->$exists("lease-time") ) {
        if ( $vc->$exists("lease-time default") ) {
            my $val = $vc->$returnValue("lease-time default");
            write_cf($indent);
            write_cf_nl("default-lease-time $val");
        }
        if ( $vc->$exists("lease-time maximum") ) {
            my $val = $vc->$returnValue("lease-time maximum");
            write_cf($indent);
            write_cf_nl("max-lease-time $val");
        }
        if ( $vc->$exists("lease-time minimum") ) {
            my $val = $vc->$returnValue("lease-time minimum");
            write_cf($indent);
            write_cf_nl("min-lease-time $val");
        }
    }
}

#
# validate a subnet address.
# 2001:db6:100::100/64 is not a valid subnet address
# 2001:db6:100::0/64 is a valid subnet address
#
sub is_valid_subnet_addr {
    my $network = shift;
    my $naipNet = $network->network();

    return ( $network == $naipNet );
}

#
# check address range conflicts
#
sub check_range_conflicts {
    my ( $ranges_start_ref, $ranges_stop_ref ) = @_;

    # local variables
    my @naip_conflict_start;
    my @naip_conflict_stop;
    my @zero_to_ranges;
    my $start_count = 0;
    my $stop_count  = 0;
    my $range_count = scalar(@$ranges_start_ref) - 1;

    foreach my $conflict_start (@$ranges_start_ref) {
        $naip_conflict_start[$start_count] = new NetAddr::IP($conflict_start);
        $start_count++;
    }
    foreach my $conflict_stop (@$ranges_stop_ref) {
        $naip_conflict_stop[$stop_count] = new NetAddr::IP($conflict_stop);
        $stop_count++;
    }

    @zero_to_ranges = ( 0 .. $range_count );
    for my $i (@zero_to_ranges) {
        for my $j (@zero_to_ranges) {
            if ( $i == $j ) {
                next;
            }
            else {
                if (    ( $naip_conflict_start[$j] <= $naip_conflict_start[$i] )
                    and ( $naip_conflict_start[$i] <= $naip_conflict_stop[$j] )
                  )
                {
                    print STDERR <<"EOM";
Conflicting DHCPv6 lease ranges: Start IP '@$ranges_start_ref[$i]'
lies in DHCPv6 lease range '@$ranges_start_ref[$j]'-'@$ranges_stop_ref[$j]'.
EOM
                    $error = 1;
                }
                elsif ( ( $naip_conflict_start[$j] <= $naip_conflict_stop[$i] )
                    and ( $naip_conflict_stop[$i] <= $naip_conflict_stop[$j] ) )
                {
                    print STDERR <<"EOM";
Conflicting DHCPv6 lease ranges: Stop IP '@$ranges_stop_ref[$i]'
lies in DHCPv6 lease range '@$ranges_start_ref[$j]'-'@$ranges_stop_ref[$j]'.
EOM
                    $error = 1;
                }
            }
        }
    }
}

#
# Main section
#

my $vcDHCP = new Vyatta::Config();

# We perform cross-parameter validation checks
# This includes the following so far:
#  - Validate subnet address
#  - Check prefixes
#  - Range overlaps

# Walk the config tree
#
my $dhcpv6_server = $vcDHCP->$exists("$config_prefix dhcpv6-server");

if ($dhcpv6_server) {
    $vcDHCP->setLevel("$config_prefix dhcpv6-server shared-network-name");
    @names = $vcDHCP->$listNodes();
    if ( @names == 0 ) {
        print STDERR <<"EOM";
No DHCPv6 shared networks configured.
At least one DHCPv6 shared network must be configured.
EOM
        exit 2;
    }

    foreach my $name (@names) {
        my @subnets = $vcDHCP->$listNodes("$name subnet");
        die
"No DHCPv6 lease subnets configured for shared network name '$name'.\n"
          if ( @subnets == 0 );

        foreach my $subnet (@subnets) {
            my $naipNetwork = new NetAddr::IP("$subnet");

            die "Invalid DHCPv6 lease subnet '$subnet' configured.\n"
              if ( !defined($naipNetwork)
                || !is_valid_subnet_addr($naipNetwork) );

            my @prefixes =
              $vcDHCP->$listNodes("$name subnet $subnet address-range prefix");

            my @ranges =
              $vcDHCP->$listNodes("$name subnet $subnet address-range start");

            my @prefix_delegations =
              $vcDHCP->$listNodes("$name subnet $subnet prefix-delegation start");

            if ( @ranges == 0 && @prefixes == 0 && @prefix_delegations == 0 ) {
                print STDERR <<"EOM";
At least one start-stop range, one prefix or prefix delegation must be configured for $subnet to exclude IP
EOM
                $error = 1;
            }
            else {
                # validate range6
                if ( @ranges != 0 ) {
                    my @ranges_stop;
                    my $ranges_stop_count = 0;

                    foreach my $start (@ranges) {
                        my $naipStart = new NetAddr::IP($start);

                        #Check to see if the start IP is within our subnet
                        if ( !$naipStart->within($naipNetwork) ) {
                            print STDERR <<"EOM";
Start DHCPv6 lease IP '$start' is outside of the DHCPv6 lease network '$subnet'
under shared network '$name'.
EOM
                            $error = 1;
                        }

                        #Get DHCPv6 stop range
                        my $stop = $vcDHCP->$returnValue(
                          "$name subnet $subnet address-range start $start stop");

                        if ( defined $stop ) {
                            my $naipStop = new NetAddr::IP($stop);
                            if ( !$naipStop->within($naipNetwork) ) {
                                print STDERR <<"EOM";
Stop DHCPv6 lease IP '$stop' is outside of the DHCPv6 lease network '$subnet'
under shared network '$name'.
EOM
                                $error = 1;
                            }

                            if ( $naipStop < $naipStart ) {
                                print STDERR <<"EOM";
Stop DHCPv6 lease IP '$stop' should be an address equal to or later
than the Start DHCPv6 lease IP '$start'
EOM
                                $error = 1;
                            }
                            $ranges_stop[$ranges_stop_count] = $stop;
                            $ranges_stop_count++;
                        }
                        else {
                            print STDERR
"Stop DHCPv6 lease IP not defined for Start DHCPv6 lease IP '$start'\n";
                            $error = 1;
                        }
                    }    # end of foreach $start

                    # check range confilcts
                    if ( $error == 0 ) {
                        check_range_conflicts( \@ranges, \@ranges_stop );
                    }
                }    # end of if @ranges != 0

                # check prefixes
                foreach my $ipv6_prefix (@prefixes) {
                    my $naipPrefix = new NetAddr::IP($ipv6_prefix);

                    #Check to see if the prefix is within our subnet
                    if ( !$naipPrefix->within($naipNetwork) ) {
                        print STDERR <<"EOM";
DHCPv6 IPv6 prefix is outside of the DHCPv6 lease network '$subnet'
under shared network '$name'.
EOM
                        $error = 1;
                    }
                }

                # validate prefix delegation
                foreach my $pdStart (@prefix_delegations) {
                    my $zero = "0";
                    my $naipPdStart = new NetAddr::IP($pdStart);

                    if ( $naipPdStart ) {
                        #Check to see if the start prefix is within our subnet
                        if ( !$naipPdStart->within($naipNetwork) ) {
                            print STDERR <<"EOM";
Start DHCPv6 prefix delegation '$pdStart' is outside of the DHCPv6 lease
network '$subnet' under shared network '$name'.
EOM
                            $error = 1;
                        }

                        #Get DHCPv6 stop prefix
                        my $pdStop = $vcDHCP->$returnValue(
                          "$name subnet $subnet prefix-delegation start $pdStart stop");

                        if ( defined $pdStop ) {
                            my $naipPdStop = new NetAddr::IP($pdStop);

                            if ( $naipPdStop ) {
                                #Check to see if the start prefix is within our subnet
                                if ( !$naipPdStop->within($naipNetwork) ) {
                                    print STDERR <<"EOM";
Stop DHCPv6 prefix delegation '$pdStop' is outside of the DHCPv6 lease
network '$subnet' under shared network '$name'.
EOM
                                    $error = 1;
                                }

                                if ( $naipPdStop < $naipPdStart ) {
                                    print STDERR <<"EOM";
Stop DHCPv6 prefix delegation '$pdStop' should be an address equal to or later
than the Start DHCPv6 prefix delegation '$pdStart'
EOM
                                    $error = 1;
                                }
                            } else { #$naipPdStop is invalid
                                print STDERR <<"EOM";
Stop DHCPv6 prefix delegation '$pdStop' is invalid 
EOM
                                $error = 1;
                            }
                        }
                    } else { #$naipPdStart is invalid
                        print STDERR <<"EOM";
Start DHCPv6 prefix delegation '$pdStart' is invalid 
EOM
                        $error = 1;
                    }
                }    #end of foreach my $pdStart
            }    # end of if ( @ranges == 0 && @prefixes == 0 ) ... else
        }    # end of foreach my $subnet
    }    #end of foreach my $name
}

if ($error) {
    print STDERR
      "DHCPv6 server configuration commit aborted due to error(s).\n";
    exit(1);
}

if ($dhcpv6_server) {

    # Open the config file
    #
    open( $config_filehandle, '>', $config_filename )
      or die "Can't open config file for writing: $config_filename ($!)\n";

    printf("Generating the DHCPv6 config file...\n");

    # Write some comments so people know where it came from.
    #
    printf( $config_filehandle
"# This file is auto-generated by the Vyatta configuration sub-system.\n"
    );
    printf( $config_filehandle "# Do not edit it by hand.\n" );
    my $iam = `whoami`;
    chomp($iam);
    printf( $config_filehandle "# Auto-generated by: $iam\n" );
    my $date_time = `date`;
    chomp($date_time);
    printf( $config_filehandle "# Auto-generated on: $date_time\n" );
    printf( $config_filehandle "#\n" );

    printf( $config_filehandle "db-time-format local;\n" );

    $vcDHCP->setLevel("$config_prefix dhcpv6-server");

    if ( $vcDHCP->$exists("preference") ) {
        my $preference = $vcDHCP->$returnValue("preference");
        write_cf_nl("option dhcp6.preference $preference");
    }

    my @mappings = $vcDHCP->$listNodes("static-mapping");
    foreach my $map (@mappings) {
	write_cf("host $map {\n");

	# host statements
	# host-identifer option dhcp6.client-id
	#
	if ( $vcDHCP->$exists("static-mapping $map identifier") ) {
	    my $id =
		$vcDHCP->$returnValue("static-mapping $map identifier");
	    my $client_duid = Vyatta::DHCPv6Duid->new($id);
            if ( defined $client_duid) {
	        my $option_duid = $client_duid->id();
	        write_cf_nl(
		    "    host-identifier option dhcp6.client-id $option_duid");
            } else {
	        write_cf_nl(
		    "    hardware ethernet $id");
	    }
	}

	# host declarations
	#
	if ( $vcDHCP->$exists("static-mapping $map ipv6-address") ) {
	    my $addr =
		$vcDHCP->$returnValue("static-mapping $map ipv6-address");
	    write_cf_nl("    fixed-address6 $addr");
	}
	write_cf("}\n");
    }

    my $path = "$config_prefix dhcpv6-server shared-network-name";
    $vcDHCP->setLevel($path);
    @names = $vcDHCP->$listNodes();
    foreach my $name (@names) {

        $vcDHCP->setLevel($path);
        write_cf("shared-network $name {\n");

        my @subnets = $vcDHCP->$listNodes("$name subnet");
        foreach my $subnet (@subnets) {

            # shared-network subnet statements
            #
            write_cf("    subnet6 $subnet {\n");

            $vcDHCP->setLevel("$path $name subnet $subnet");
            write_lease_limits( "\t", $vcDHCP );

            my @servers = $vcDHCP->$returnValues("name-server");
            if (@servers) {
                foreach my $server (@servers) {
                    push_list("$server");
                }
                write_list("\toption dhcp6.name-servers");
            }

            my @domains = $vcDHCP->$returnValues("domain-search");
            if (@domains) {
                foreach my $domain (@domains) {
                    push_list("$domain");
                }
                write_domain_list("\toption dhcp6.domain-search");
            }

            my @sip_servers = $vcDHCP->$returnValues("sip-server-name");
            if (@sip_servers) {
                foreach my $sip_server (@sip_servers) {
                    push_list("$sip_server");
                }
                write_domain_list("\toption dhcp6.sip-servers-names");
            }

            @sip_servers = $vcDHCP->$returnValues("sip-server-address");
            if (@sip_servers) {
                foreach my $sip_server (@sip_servers) {
                    push_list("$sip_server");
                }
                write_list("\toption dhcp6.sip-servers-addresses");
            }

            if ( $vcDHCP->$exists("nis-domain") ) {
                my $domain = $vcDHCP->$returnValue("nis-domain");
                push_list("$domain");
                write_domain_list("\toption dhcp6.nis-domain-name");
            }

            my @nis_servers = $vcDHCP->$returnValues("nis-server");
            if (@nis_servers) {
                foreach my $nis_server (@nis_servers) {
                    push_list("$nis_server");
                }
                write_list("\toption dhcp6.nis-servers");
            }

            if ( $vcDHCP->$exists("nisplus-domain") ) {
                my $domain = $vcDHCP->$returnValue("nisplus-domain");
                push_list("$domain");
                write_domain_list("\toption dhcp6.nisp-domain-name");
            }

            my @nisplus_servers = $vcDHCP->$returnValues("nisplus-server");
            if (@nisplus_servers) {
                foreach my $nisplus_server (@nisplus_servers) {
                    push_list("$nisplus_server");
                }
                write_list("\toption dhcp6.nisp-servers");
            }

            my @sntp_servers = $vcDHCP->$returnValues("sntp-server");
            if (@sntp_servers) {
                foreach my $sntp_server (@sntp_servers) {
                    push_list("$sntp_server");
                }
                write_list("\toption dhcp6.sntp-servers");
            }

            # shared-network subnet declarations
            #
            my @prefixes = $vcDHCP->$listNodes("address-range prefix");
            foreach my $prefix (@prefixes) {
                if (
                    $vcDHCP->$exists("address-range prefix $prefix temporary") )
                {
                    my $stop = $vcDHCP->$returnValue(
                        "address-range prefix $prefix temporary");
                    write_cf_nl("\trange6 $prefix temporary");
                }
                else {
                    write_cf_nl("\trange6 $prefix");
                }
            }

            my @ranges = $vcDHCP->$listNodes("address-range start");
            foreach my $start (@ranges) {
                my $stop =
                  $vcDHCP->$returnValue("address-range start $start stop");
                write_cf_nl("\trange6 $start $stop");
            }

            my @delegations = $vcDHCP->$listNodes("prefix-delegation start");
            foreach my $start (@delegations) {
                if (
                    $vcDHCP->$exists("prefix-delegation start $start stop")
                    && $vcDHCP->$exists(
                        "prefix-delegation start $start prefix-length")
                  )
                {
                    my $stop = $vcDHCP->$returnValue(
                        "prefix-delegation start $start stop");
                    my $plen = $vcDHCP->$returnValue(
                        "prefix-delegation start $start prefix-length");
                    write_cf_nl("\tprefix6 $start $stop /$plen");
                }
            }
            write_cf("    }\n");
        }
        write_cf("}\n");
    }

    # Close the config file, we're done!
    #
    close($config_filehandle);
}
else {
    if ($op_mode_flag) {
        printf("DHCPv6 server is not configured.\n");
    }

    # No error message required when run in config mode since
    # it is expected behavior.
    exit 0;
}

exit 0;

