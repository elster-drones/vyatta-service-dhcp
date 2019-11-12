#!/usr/bin/perl

# Module: vyatta-validate-duid.pl
#
# **** License ****
# Copyright (c) 2019 AT&T Intellectual Property.  All rights reserved.
# Copyright (c) 2015 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: Judy Hao
# Date: March 2015
# Description: Script to validate duid 
#
# **** End License ****

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5/";

use Getopt::Long;
use Vyatta::DHCPv6Duid;

my $duid;

GetOptions(
    "duid=s"   => \$duid,
    );

my $client_duid = Vyatta::DHCPv6Duid->new($duid);

die "Invalid DUID $duid"
  unless (defined($client_duid));

exit 0

