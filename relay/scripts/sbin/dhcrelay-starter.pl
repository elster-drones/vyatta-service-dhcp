#!/usr/bin/perl
#
# Copyright (c) 2019 AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";
use Vyatta::Config;
use Vyatta::Interface;
use Getopt::Long;

my ($rtinst, $init, $op_mode);
GetOptions(
    "rtinst=s"    => \$rtinst,
    "init=s"      => \$init,
    "op-mode!"    => \$op_mode
);

my $config_prefix;
if ( !defined $rtinst ) {
    $rtinst = "default";
}
if ( $rtinst eq "default" ) {
    $config_prefix = "service";
}
else {
    $config_prefix = "routing routing-instance $rtinst service";
}

my $exists = ($op_mode ? 'existsOrig' : 'exists');
my $returnValues = ($op_mode ? 'returnOrigValues' : 'returnValues');
my $returnValue = ($op_mode ? 'returnOrigValue' : 'returnValue');

my $vc     = new Vyatta::Config();
my $vcRoot = new Vyatta::Config();
my $cmd_args = "";

$vc->setLevel("$config_prefix dhcp-relay");
if ( $vc->$exists('.') ) {

    my $port = $vc->$returnValue("relay-options port");
    if ( ( defined $port )  && ( $port ne '' ) ) {
        $cmd_args .= " -p $port";
    }

    my @listen_interfaces = $vc->$returnValues("listen-interface");
    foreach my $ifname (@listen_interfaces) {
        my $intf = new Vyatta::Interface($ifname);
        die "DHCP relay configuration error."
          . "Unable to determine type of interface \"$ifname\".\n"
          unless $intf;

        die
"DHCP relay configuration error.  DHCP relay listen-interface \"$ifname\" specified has not been configured.\n"
          unless $vcRoot->$exists( $intf->path() );

        $cmd_args .= " -i " . $intf->name();
    }

    my @upstream_interfaces = $vc->$returnValues("upstream-interface");
    foreach my $ifname (@upstream_interfaces) {
        my $intf = new Vyatta::Interface($ifname);
        die "DHCP relay configuration error."
          . "Unable to determine type of interface \"$ifname\".\n"
          unless $intf;

        die
"DHCP relay configuration error.  DHCP relay upstream-interface \"$ifname\" specified has not been configured.\n"
          unless $vcRoot->$exists( $intf->path() );

        $cmd_args .= " -i " . $intf->name();
    }

    my $count = $vc->$returnValue("relay-options hop-count");
    if ( ( defined $count ) && ( $count ne '' ) ) {
        $cmd_args .= " -c $count";
    }

    my $length = $vc->$returnValue("relay-options max-size");
    if ( ( defined $length ) && ( $length ne '' ) ) {
        $cmd_args .= " -A $length";
    }

    my $rap = $vc->$returnValue("relay-options relay-agents-packets");
    if ( ( defined $rap ) && ( $rap ne '' ) ) {
        $cmd_args .= " -m $rap";
    }

    my @servers = $vc->$returnValues("server");
    if ( @servers == 0 ) {
        die
"DHCP relay configuration error.  No DHCP relay server(s) configured.  At least one DHCP relay server required.\n";
    }

    foreach my $server (@servers) {
        die
"DHCP relay configuration error.  DHCP relay server with an empty name specified.\n"
          if ( $server eq '' );

        $cmd_args .= " $server";
    }
}

if ( $init ne '' ) {
    if ( $cmd_args eq '' ) {
        exec "$init stop $rtinst";
    }
    else {
        exec "$init restart $rtinst $cmd_args";
    }
}

