#!/usr/bin/perl
# Module: listento-interfaces.pl
#
# **** License ****
#
# Copyright (c) 2019 AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2007-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";

use Getopt::Long;
my $ipversion;
my @interfaces;
my $listentointfs;
my $opmode;
my $vrf;
my $config_prefix;

GetOptions(
    "ipversion=s"        => \$ipversion,
    "vrf=s"              => \$vrf,
    "opmode"             => \$opmode,
);

if ( $vrf eq "default" ) {
    $config_prefix = "service";
}
else {
    $config_prefix = "routing routing-instance $vrf service";
}

use Vyatta::Config;
my $vcDHCP = new Vyatta::Config();

# Use proper Vyatta PERL APIs based on opmode flag
my $exists = ( $opmode ? "existsOrig" : "exists" );
my $returnValues = ( $opmode ? "returnOrigValues" : "returnValues");

if ( defined $ipversion && $ipversion eq "ipv4" ) {
    if ( $vcDHCP->$exists("$config_prefix dhcp-server listento") ) {
        $vcDHCP->setLevel("$config_prefix dhcp-server listento");

        @interfaces = $vcDHCP->$returnValues("interface");
    }
} elsif ( defined $ipversion && $ipversion eq "ipv6" ) {
    if ( $vcDHCP->$exists("$config_prefix dhcpv6-server listento") ) {
        $vcDHCP->setLevel("$config_prefix dhcpv6-server listento");

        @interfaces = $vcDHCP->$returnValues("interface");
    }
}

$listentointfs .= join " ", @interfaces;

print $listentointfs;
