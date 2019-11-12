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
our @EXPORT_OK = qw(generate_dhclient_intf_files);

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

1;
