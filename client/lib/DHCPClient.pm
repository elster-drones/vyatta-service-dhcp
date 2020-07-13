#
# Module: Vyatta::DHCPClient
#
# **** License ****
#
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2015, Brocade Comunications Systems, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Date: March 2015
# Description: Library containing functions for DHCP client commands
#
# **** End License ****
#

package Vyatta::DHCPClient;

use strict;
use Vyatta::ioctl;

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(is_dhcp_enabled);
our @EXPORT_OK = qw(generate_dhclient_intf_files get_dhclient_options);

use Vyatta::Config;
use Vyatta::Interface;

# check if interface is configured to get an IP address using dhcp
sub is_dhcp_enabled {
    my ( $name, $mode ) = @_;
    my $intf = new Vyatta::Interface($name);
    return unless $intf;

    my $config = new Vyatta::Config;

    $config->setLevel( $intf->path() );
    if ( $mode eq 'cfg_mode' ) {
        return 1
          if ( $config->exists("address dhcp")
            || $config->isDeleted("address dhcp") );
    } elsif ( $mode eq 'op_mode' ) {
        return 1 if ( $config->existsOrig("address dhcp") );
    }

    return;
}

# return dhclient related files for interface
sub generate_dhclient_intf_files {
    my $intf         = shift;
    my $dhclient_dir = '/var/lib/dhcp/';
    my $dhclient_pid_dir = '/var/run/';

    my $intf_config_file     = $dhclient_dir . 'dhclient_' . $intf . '.conf';
    my $intf_process_id_file = $dhclient_pid_dir . 'dhclient_' . $intf . '.pid';
    my $intf_leases_file     = $dhclient_dir . 'dhclient_' . $intf . '.leases';
    my $intf_env_file        = $dhclient_dir . 'dhclient_' . $intf . '.env';
    return ( $intf_config_file, $intf_process_id_file, $intf_leases_file, $intf_env_file );

}

# This function is used to read the dhcp option file.
# Input - dhcp option filename.
# Output - dhcp option, option code, option type and interface.
# DHCP option file format should be as below
# DHCP_OPT=<option_parameter>
# DHCP_OPT_CODE=<Number>
# DHCP_OPT_TYPE=<type eg., text, ipaddress, etc>
# DHCP_INTF=<Interface name>
sub load_dhcp_option_params {
    my ($f, $ifname) = (@_);
    return unless -s $f;
    my $dhcp_opt = Config::Tiny->read($f);
    my $t = $dhcp_opt->{_};
    return
      unless defined( $t->{'DHCP_OPT'} )
          and $t->{'DHCP_OPT'} ne ""
          and defined( $t->{'DHCP_OPT_CODE'} )
          and $t->{'DHCP_OPT_CODE'} ne ""
          and defined( $t->{'DHCP_OPT_TYPE'} )
          and $t->{'DHCP_OPT_TYPE'} ne ""
          and defined( $t->{'DHCP_INTF'} )
          and $t->{'DHCP_INTF'} eq $ifname;
    return ( $t->{'DHCP_OPT'},
             $t->{'DHCP_OPT_CODE'},
             $t->{'DHCP_OPT_TYPE'} );
}

# This function is used to frame the dhclient option with code and type.
sub get_dhcp_option_str {
    my ( $name, $code, $type ) = (@_);
    return "option $name code $code = $type;";
}

# This function is used to frame the dhclientv6 option with code and type.
sub get_dhcpv6_option_str {
    my ( $name, $code, $type ) = (@_);
    return "option dhcp6.$name code $code = $type;";
}

# return dhclient global and request options
sub get_dhclient_options {
    my ( $intf, $dhcp_type ) = @_;
    my $dhclient_opt_dir = '/run/dhcp/client';
    my $dhclient_global_buf;
    my $dhclient_req_buf;

    # Open the dhcp option file directory
    opendir (my $opt_dir, "$dhclient_opt_dir/$intf") or return;
    # Read all the files present in the directory
    while (my $file = readdir $opt_dir) {
      if (index ($file, ".option") != -1) {
        my ($opt, $opt_code, $opt_type) = load_dhcp_option_params("$dhclient_opt_dir/$intf/$file", $intf);
        if ( $dhcp_type eq "ipv4" ) {
          # Update the dhclient global and request option with code and type
          $dhclient_global_buf .= get_dhcp_option_str($opt, $opt_code, $opt_type) . "\n\n" if defined $opt;
          $dhclient_req_buf .= ", " . $opt if defined $opt;
        } elsif ( $dhcp_type eq "ipv6" ) {
          # Update the dhclientv6 global and request option with code and type
          $dhclient_global_buf .= get_dhcpv6_option_str($opt, $opt_code, $opt_type) . "\n\n" if defined $opt;
          $dhclient_req_buf .= "dhcp6." . $opt . ", " if defined $opt;
        }
      }
    }
    closedir $opt_dir;

    return ( $dhclient_global_buf, $dhclient_req_buf );
}

1;
