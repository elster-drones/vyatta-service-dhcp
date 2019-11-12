#!/usr/bin/perl

# Module: dhcv6relay-status.pl
#
# **** License ****
# 
# Copyright (c) 2019 AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2014-2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2010-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: Bob Gilligan
# Date: April 2010
# Description: Script to display status about DHCPv6 relay agent
#
# **** End License ****

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";

use Getopt::Long;
use Vyatta::Config;

# Globals
my $op_mode_flag;       # Indicates we are running in op mode if set.
my $rtinst;

GetOptions(
    "op_mode"           => \$op_mode_flag,
    "rtinst=s"          => \$rtinst,
);

#
# Main Section
#
my $config_prefix;

if ( $rtinst eq "default" ) {
    $config_prefix = "service";
} else {
    $config_prefix = "routing routing-instance $rtinst service";
}

my $vcDHCP = new Vyatta::Config();

my $exists=$vcDHCP->existsOrig("$config_prefix dhcpv6-relay");

my $configured_count=0;
if ($exists) {
    printf("DHCPv6 Relay Agent is configured in routing-instance $rtinst ");
    $configured_count++;
} else {
    printf("DHCPv6 Relay Agent is not configured in routing-instance $rtinst ");
}

my $running_count=0;
my $pidfile = "/var/run/dhcrelayv6/dhcv6relay_vrf_$rtinst.pid";
if ( -e $pidfile ) {
    my $output = `cat $pidfile`;
    if ( $output ) {
       if ($configured_count == 0) {
           printf("but ");
       } else {
           printf("and ");
       }

       printf("is running.\n");
       $running_count++;
     }
}

if ($running_count == 0) {
       if ($configured_count == 0) {
           printf("and ");
       } else {
           printf("but ");
       }
    printf("is not running.\n");
}

exit 0;

