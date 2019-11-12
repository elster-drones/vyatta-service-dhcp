#
# Module Vyatta::DHCPServerOpMode
#
# **** License ****
#
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2014, Brocade Comunications Systems, Inc.
# All Rights Reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2011-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: John Southworth
# Date: January 2011
# Description: Library containing functions for DHCP operational commands
#
# **** End License ****
#

package Vyatta::DHCPServerOpMode;

use lib "/opt/vyatta/share/perl5/";
use strict;
use NetAddr::IP;

sub get_active_leases {
    my $rtinst = shift;
    my $lease_file = "/config/dhcpd/dhcpd_vrf_$rtinst.leases";
    open( my $leases, '<', $lease_file );
    my $ip;
    my $pool;
    my $lease;
    my %active_leases_hash = ();

    while (<$leases>){
      my $line = $_;
      if ($line =~ /lease\s(.*)\s\{/){
        $ip = $1;
      }
      next if (!defined($ip));
      if ($line =~ /shared-network:\s(.*)/) {
        $pool = $1;
      }
      next if (!defined($pool));

      if ( $line =~ /^\s+binding\sstate\s(.*?)\;/ ) {
        if ( defined $1 ) {
          $lease->{state} = $1;
          $lease->{pool} = $pool;
        }
      }

      if ( $line =~ /^}/ ) {
        $active_leases_hash{"$ip"} = $lease;
        $ip = undef;
        $pool = undef;
        $lease = undef;
      }
    }

    while ( my ($lease_ip, $lease) = each (%active_leases_hash) ) {
      if ( $lease->{state} ne "active" ) {
        delete $active_leases_hash{"$lease_ip"};
      }
    }
    return \%active_leases_hash;
}

sub get_pool_info {
  my $rtinst = shift;
  my $conf_file = "/opt/vyatta/etc/dhcpd/dhcpd_vrf_$rtinst.conf";
  open( my $conf, '<', $conf_file );
  my $level = 0;
  my $shared_net;
  my %shared_net_hash = ();

  while (<$conf>){
    my $line = $_;
    $level++ if ( $line =~ /{/ );
    $level-- if ( $line =~ /}/ );
    if ($line =~ /shared-network\s(.*)\s\{/){
      $shared_net = $1;
    } elsif ($line =~ /range\s(.*?)\s(.*?);/) {
      my $start = new NetAddr::IP("$1");
      my $stop = new NetAddr::IP("$2");
      my $pool_info;
      $pool_info->{POOL_SIZE} = ($stop - $start + 1);
      if (defined($shared_net_hash{$shared_net})) {
          push @{ $shared_net_hash{$shared_net} }, $pool_info;
      } else {
          $shared_net_hash{$shared_net} = [ $pool_info ];
      }
    } 
  }

  #sanity check the file
  if ($level != 0){
    die "Invalid dhcpd.conf, mismatched braces";
  }
  return \%shared_net_hash;
}

sub print_stime_etime {
  my $rtinst = shift;

  my $unit = "vyatta-service-dhcp-server";
  if ($rtinst ne "default") {
    $unit .= "@" . "$rtinst";
  }  

  my $pid = `systemctl show $unit -p MainPID --value`;

  if ($pid == 0) {
    my $msg = "DHCP server not running";
    if ($rtinst ne "default") {
      $msg .= ", routing instance: $rtinst";
    }  
    $msg .= "\n";
    print $msg;
    exit 0;
  }

  my $format = "%-39s %s";
  my $stime_str ="Start time:";
  my $etime_str ="Up time:";
  my $stime = `ps -o lstart= -p $pid 2> /dev/null`;
  my $etime = `ps -o etime= -p $pid 2> /dev/null`;
  $etime =~ s/^\s+//;
  print "\n";
  if ($stime ne "") {
    printf($format, $stime_str, $stime);
  }
  if ($etime ne "") {
    printf($format, $etime_str, $etime);
  }
}

sub print_pkgs_stat {
  my $rtinst = shift;
  my $msg = "Message";
  my $rcv = "Received";
  my $sent = "Sent";
  my $discover = "DHCPDISCOVER";
  my $request = "DHCPREQUEST";
  my $decline = "DHCPDECLINE";
  my $release = "DHCPRELEASE";
  my $inform = "DHCPINFORM";
  my $offer = "DHCPOFFER";
  my $ack = "DHCPACK";
  my $nak = "DHCPNAK";

  my $unit = "vyatta-service-dhcp-server";
  if ($rtinst ne "default") {
    $unit .= "@" . "$rtinst";
  }  

  my $counters;
  my $error = `systemctl kill $unit -s USR1 2>&1`;
  if ($error eq "") {
    my $counter_file = "/var/run/dhcpd/dhcpd_vrf_$rtinst.cntr";
    open( $counters, '<', $counter_file );
  }

  my $discover_count = 0;
  my $request_count = 0;
  my $decline_count = 0;
  my $release_count = 0;
  my $inform_count = 0;
  my $offer_count = 0;
  my $ack_count = 0;
  my $nak_count = 0;

  while (<$counters>){
    my $line = $_;
    if ($line =~ /$discover\s(.*)/){
      $discover_count = $1;
    } elsif ($line =~ /$request\s(.*)/) {
      $request_count = $1;
    } elsif ($line =~ /$decline\s(.*)/) {
      $decline_count = $1;
    } elsif ($line =~ /$release\s(.*)/) {
      $release_count = $1;
    } elsif ($line =~ /$inform\s(.*)/) {
      $inform_count = $1;
    } elsif ($line =~ /$offer\s(.*)/) {
      $offer_count = $1;
    } elsif ($line =~ /$ack\s(.*)/) {
      $ack_count = $1;
    } elsif ($line =~ /$nak\s(.*)/) {
      $nak_count = $1;
    }
  }

  my $format = "%-39s %s\n";
  print "\n";
  printf($format, $msg, $rcv);
  printf($format, $discover, $discover_count);
  printf($format, $request, $request_count);
  printf($format, $decline, $decline_count);
  printf($format, $release, $release_count);
  printf($format, $inform, $inform_count);
  print "\n";
  printf($format, $msg, $sent);
  printf($format, $offer, $offer_count);
  printf($format, $ack, $ack_count);
  printf($format, $nak, $nak_count);
}

sub print_stats {
  my $routing_inst = shift;
  my $pool_filter = shift;
  if (!(defined $pool_filter)) {
    print_stime_etime($routing_inst);
    print_pkgs_stat($routing_inst);
  }

  my %pool_size_hash = ();
  my %pool_used_hash = ();
  my $pool_info = get_pool_info($routing_inst);
  my $active_leases = get_active_leases($routing_inst);
  my $format = "%-39s %-11s %-11s %s\n";
  print "\n";
  printf($format, "pool", "pool size", "# leased", "# avail");
  printf($format, "----", "---------", "--------", "-------");

  ## get total pool size for each pool
  for my $pool (keys %{$pool_info}) {
    if (defined ($pool_filter)) {
      next if ($pool ne $pool_filter);
    }
    my @my_pools = @{ $pool_info->{$pool} };
    foreach my $my_pool (@my_pools) {
      $pool_size_hash{$pool} += $my_pool->{POOL_SIZE};
    }
  }

  ## get number of leased ip for each pool
  while ( my ($ip_lease, $lease) = each (%{$active_leases}) ) {
    POOL: for my $pool (keys %{$pool_info}) {
      if (defined ($pool_filter)) {
        next if ($pool ne $pool_filter);
      }
      if ( $lease->{pool} eq $pool ) {
          $pool_used_hash{$pool} += 1;
          last POOL;
      }
    }
  }

  ## print pool information
  foreach my $pool_name (keys %pool_size_hash) {
    my $pool_size = $pool_size_hash{$pool_name};
    my $used = $pool_used_hash{$pool_name};
    if (!defined $used) {
      $used = 0;
    }
    printf($format, $pool_name, $pool_size, $used, $pool_size - $used);
  }

  print "\n";
}

return 1;
