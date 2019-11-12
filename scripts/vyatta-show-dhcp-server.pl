#!/usr/bin/perl
#
# Script: vyatta-show-dhcp-server
#
# **** License ****
#
# Copyright (c) 2019 AT&T Intellectual Property. All rights reserved.
# Copyright (c) 2014, Brocade Comunications Systems, Inc.
# All Rights Reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2008-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: John Southworth
# Date: January 2011
# Description: Wrapper script for DHCP operational commands 
#
# **** End License ****
#

use strict;
use warnings;
use lib '/opt/vyatta/share/perl5';
use Vyatta::DHCPServerOpMode;
use Getopt::Long;

my ($show_stats, $rtinst, $pool);
GetOptions("show-stats!" => \$show_stats,
           "rtinst=s"    => \$rtinst,
           "pool=s"      => \$pool);

if (defined $show_stats){
  Vyatta::DHCPServerOpMode::print_stats($rtinst, $pool);
}
