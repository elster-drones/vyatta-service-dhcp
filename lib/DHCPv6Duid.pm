#
# Module Vyatta::DHCPv6Duid
#
# **** License ****
#
# Copyright (c) 2019, AT&T Intellectual Property. All rights reserved.
#
# Copyright (c) 2015, Brocade Comunications Systems, Inc.
# All Rights Reserved.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2011-2013 Vyatta, Inc.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
# Author: Ian Wilson
# Date: February 2015
# Description: Library containing functions for DHCP DUID operations
#
# **** End License ****
#

package Vyatta::DHCPv6Duid;

use lib "/opt/vyatta/share/perl5/";

use strict;
use warnings;

my $DUID_EPOCH_OFFSET = 946684800;    # plus 30 years to get to unix time epoch

my $debug = 0;

#
# RFC 3315 Section 9, DHCP Unique Identifier
# RFC 6355 UUID-Based DHCPv6 Unique Identifier (DUID-UUID)
#
my $DUID_TYPE_MIN    = 1;
my $DUID_TYPE_MAX    = 4;
my $DUID_NOCTETS_MIN = 10;

my %type_string = (
    1 => "Time+Link Layer (DUID-LLT)",
    2 => "Vendor Assigned (DUID-EN)",
    3 => "Link Layer (DUID-LL)",
    4 => "Unique Identifier (DUID-UUID)"
);

my %type_string_short = (
    1 => "LL_TIME",
    2 => "EN",
    3 => "LL",
    4 => "UUID"
);

#
# Indexed by duid type
#
my %contains_hwtype = ( 1 => 1, 2 => 0, 3 => 1, 4 => 0 );
my %contains_time   = ( 1 => 1, 2 => 0, 3 => 0, 4 => 0 );
my %contains_ll     = ( 1 => 1, 2 => 0, 3 => 1, 4 => 0 );
my %contains_ent    = ( 1 => 0, 2 => 1, 3 => 0, 4 => 0 );
my %contains_id     = ( 1 => 0, 2 => 1, 3 => 0, 4 => 0 );
my %contains_uuid   = ( 1 => 0, 2 => 0, 3 => 0, 4 => 1 );

#
#  DUID-LLT:
#
#   0                   1                   2                   3
#   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#  |               1               |    hardware type (16 bits)    |
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#  |                        time (32 bits)                         |
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#  .                                                               .
#  .             link-layer address (variable length)              .
#  .                                                               .
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#
# e.g. 00:01:00:01:1c:62:2a:74:52:54:00:00:01:02
#
# DUID-EN:
#
#   0                   1                   2                   3
#   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#  |               2               |       enterprise-number       |
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#  |   enterprise-number (contd)   |                               |
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+                               |
#  .                           identifier                          .
#  .                       (variable length)                       .
#  .                                                               .
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#
# e.g. 00:02:00:00:00:09:0c:c0:84:d3:03:00:09:12
#
# DUID-EL:
#
#   0                   1                   2                   3
#   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#  |               3               |    hardware type (16 bits)    |
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#  .                                                               .
#  .             link-layer address (variable length)              .
#  .                                                               .
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#
# DUID-UUID:
#
#   0                   1                   2                   3
#   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#  |          DUID-Type (4)        |    UUID (128 bits)            |
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+                               |
#  |                                                               |
#  |                                                               |
#  |                                -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
#  |                                |
#  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
#
#
my %hw_types = (
    0   => "Reserved",
    1   => "Ethernet",
    2   => "Exp. Ethernet",
    3   => "Amateur Radio",
    4   => "Token Ring",
    5   => "Chaos",
    6   => "IEEE 802",
    7   => "ARCNET",
    8   => "Hyperchannel",
    9   => "Lanstart",
    10  => "Autonet",
    11  => "Localtalk",
    12  => "LocalNet",
    13  => "Ultra link",
    14  => "SMDS",
    15  => "Frame Relay",
    16  => "ATM",
    17  => "HDLC",
    18  => "Fiber Channel",
    19  => "ATM",
    20  => "Serial",
    21  => "ATM",
    22  => "MIL-STD-88-220",
    23  => "Metricom",
    24  => "IEEE 1394",
    25  => "MAPOS",
    26  => "Twinaxial",
    27  => "EUI-64",
    28  => "HIPARP",
    29  => "ISO 7816-3",
    30  => "ARPSec",
    31  => "IPSec",
    32  => "Infiniband",
    33  => "TIA-102",
    34  => "Wiegand",
    35  => "Pure IP",
    36  => "HW_EXP1",
    37  => "HFI",
    256 => "HW_EXP2"
);

#
# Create a DHCPv6Duid object from a string.
#
#  Strings may be in octal format or hex format. e.g.
#
# my $duid = DHCPv6Duid->new("\000\001\000\001\034b*tRT\000\000\001\002");
#
sub new {
    my ( $class, $data ) = (@_);

    # Allocate new object
    my $self = {};

    bless( $self, $class );

    # Pass everything to set()
    unless ( $self->set($data) ) {
	if ($debug) {
	    print "Error: $self->{error}\n";
	    print "$data\n";
	}
        return;
    }
    return ($self);
}

#
# Subroutine set
#
# Params  : String containing the DUID in either octal or hex format
# Returns : 1 (success) or undef (failure)
#
# Will parse DUID strings in the following formats:
#
#   00:01:00:01:1c:62:2A:74:52:54:00:00:01:02
#   0:1:0:1:1c:62:2A:74:52:54:0:0:1:2
#   \000\001\000\001\034b*tRT\000\000\001\002
#   000300010002FCA5DC1C
#   00-03-00-01-00-02-FC-A5-DC-1C
#   0-3-0-1-0-2-FC-A5-DC-1C
#
sub set {
    my $self = shift;
    my ($data) = (@_);

    # Ensure the fields are undefined
    #
    for (
        qw(enterprise_number
        error
        hex_string
        iana_hw_type
        identifier
        link_layer_address
        octal_string
        time
        type
        uuid)
      )
    {
        delete( $self->{$_} );
    }

    if ( $data =~ /^([a-f0-9]{1,2}-)+([a-f0-9]{1,2})?$/i ) {

        #
        # hex string separated by dashes.
        #
        my $hex_string = '';
        my $num;
        foreach ( split /-/, $data ) {

            # Convert hex string to number
            $num = hex($_);
            $hex_string .= sprintf( '%02x', $num );
        }
        $self->{hex_string} = $hex_string;
    }
    elsif ( $data =~ /^:?([a-f0-9]{1,2}:)+([a-f0-9]{1,2})?$/i ) {

        #
        # hex string separated by colons.
        #
        my $hex_string = '';
        my $num;
        foreach ( split /:/, $data ) {

            # Convert hex string to number
            $num = hex($_);
            $hex_string .= sprintf( '%02x', $num );
        }
        $self->{hex_string} = $hex_string;
    }
    elsif ( $data =~ /[a-f0-9]{20,40}/i ) {

        #
        # hex string with no separating character.
        #
        $self->{hex_string} = $data;
    }
    elsif ( $data =~ /^\\[0-9]{3}/ ) {

        #
        # Mixed string of octal and ascii.  (Default linux format in
        # log files.)
        #
        $self->{octal_string} = $data;
        $self->{hex_string}   = octstohexs( $self->{octal_string} );
    }

    if ( !defined( $self->{hex_string} ) ) {
	$self->{error} = "Unrecogized data format $data";
        return;
    }

    my @hex_array = unpack( '(A2)*', $self->{hex_string} );
    my $noctets = scalar @hex_array;
    if ( $noctets < $DUID_NOCTETS_MIN ) {
	$self->{error} = "Does not contain minimum number of octets $data";
        return;
    }

    my $hexs = $self->{hex_string};
    my $duid_type;

    #
    # DUID type (16 bits)
    #
    $hexs =~ s/^[a-f0-9]{4}//i;
    $self->{type} = hex($&);
    $noctets -= 2;

    if ( $self->{type} < $DUID_TYPE_MIN || $self->{type} > $DUID_TYPE_MAX ) {
	$self->{error} = "Unknown DUID type $self->{type}";
        return;
    }

    if ( $contains_hwtype{ $self->{type} } ) {

        #
        # Extract the hardware type (16 bits)
        #
        $hexs =~ s/^[a-f0-9]{4}//i;
        $self->{iana_hw_type} = hex($&);
        $noctets -= 2;

        unless ( defined( $hw_types{ $self->{iana_hw_type} } ) ) {
            $self->{error} = "Unknown hardware type $self->{iana_hw_type}";
            return;
        }
    }

    if ( $contains_time{ $self->{type} } ) {

        #
        # Extract the time (32 bits)
        #
        $hexs =~ s/^[a-f0-9]{8}//i;
        $self->{time} = hex($&);
        $noctets -= 4;
    }

    if ( $contains_ll{ $self->{type} } ) {

        #
        # Link-layer address is remaining string
        #
        $self->{link_layer_address} = $hexs;
    }

    if ( $contains_ent{ $self->{type} } ) {

        #
        # Extract the enterprise number (32 bits)
        #
        $hexs =~ s/^[a-f0-9]{8}//i;
        $self->{enterprise_number} = hex($&);
        $noctets -= 4;
    }

    if ( $contains_id{ $self->{type} } ) {
        $self->{identifier} = $hexs;
    }

    if ( $contains_uuid{ $self->{type} } ) {
        if ( $noctets != 16 ) {
            $self->{error} = "$noctets hex numbers in UUID, expected 16";
            return;
        }

        $self->{uuid} = $hexs;
    }

    return ($self);
}

#
# Returns link-layer string.
#
# Default is a hex string.  If the hardware type is ethernet *and*
# the ethernet_mac format is specified then a colon separated string
# is returned, e.g.
#
# $duid->link_layer_address(format => 'ethernet_mac');
#
sub link_layer_address {
    my ( $self, %opts ) = @_;

    my %formats = ( ethernet_mac => 1, );

    if ( $opts{format} ) {
        if ( !$formats{ $opts{format} } ) {
            return undef;
        }

        if (   $self->{link_layer_address}
            && $opts{format} eq 'ethernet_mac'
            && $self->{iana_hw_type} == 1 )
        {
            my @ethernet_mac = unpack( '(A2)*', $self->{link_layer_address} );
            return join ":", @ethernet_mac;
        }
    }
    else {
        return $self->{link_layer_address};
    }
    return undef;
}

#
# Returns the DUID as a colon-separated string.  (This is the same
# format used to specify static bindings.)
#
sub id {
    my ($self) = @_;

    my @id = unpack( '(A2)*', $self->{hex_string} );
    return join ":", @id;
}

#
# Return a short string, e.g.
#
#   LL_TIME-Ethernet(1)-0x1c62237d-52:54:00:f6:d7:11
#
sub short_string {
    my $self = shift;
    my $ret  = '';

    if ( !$self || !$self->{hex_string} ) {
        return undef;
    }

    $ret .= $type_string_short{ $self->{type} };

    if ( defined( $self->{iana_hw_type} ) ) {
        $ret .= sprintf( "-%s(%d)",
            $hw_types{ $self->{iana_hw_type} },
            $self->{iana_hw_type} );
    }

    if ( defined( $self->{time} ) ) {
        $ret .= sprintf( "-0x%x", $self->{time} );
    }
    if ( defined( $self->{link_layer_address} ) ) {
        $ret .= sprintf( "-%s",
            $self->link_layer_address( format => 'ethernet_mac' ) );
    }
    if ( defined( $self->{enterprise_number} ) ) {
        $ret .= sprintf( "-0x%4x", $self->{enterprise_number} );
    }
    if ( defined( $self->{identifier} ) ) {
        $ret .= sprintf( "-%s", $self->{identifier} );
    }
    if ( defined( $self->{uuid} ) ) {
        $ret .= sprintf( "-%s", $self->{uuid} );
    }

    return $ret;
}

#
# Return a long string, e.g.
#
#   Time+Link Layer (DUID-LLT); Hardware: Ethernet(1); Time: Mon Feb  2 12:01:01 2015; Link-layer: 52:54:00:f6:d7:11
#
sub long_string {
    my $self = shift;
    my $ret  = '';

    if ( !$self || !$self->{hex_string} ) {
        return undef;
    }

    $ret .= $type_string{ $self->{type} };

    if ( defined( $self->{iana_hw_type} ) ) {
        $ret .= sprintf(
            "; Hardware: %s(%d)",
            $hw_types{ $self->{iana_hw_type} },
            $self->{iana_hw_type}
        );
    }

    if ( defined( $self->{time} ) ) {
        $ret .= "; Time: " . localtime( $self->{time} + $DUID_EPOCH_OFFSET );
    }
    if ( defined( $self->{link_layer_address} ) ) {
        $ret .= sprintf( "; Link-layer: %s",
            $self->link_layer_address( format => 'ethernet_mac' ) );
    }
    if ( defined( $self->{enterprise_number} ) ) {
        $ret .= sprintf( "; Enterprise ID: 0x%4x", $self->{enterprise_number} );
    }
    if ( defined( $self->{identifier} ) ) {
        $ret .= sprintf( "; ID: %s", $self->{identifier} );
    }
    if ( defined( $self->{uuid} ) ) {
        $ret .= sprintf( "; UUID: %s", $self->{uuid} );
    }

    return $ret;
}

#
# Return a string.
#
# Defaults to hex string.  Optional formatting paramters are 'hex',
# 'id' (colon-separated hex), 'short', or 'long', e.g.
#
#   $duid->print(format => 'long')
#
sub print {
    my ( $self, %opts ) = @_;

    my %formats = (
        hex   => 1,
        octal => 2,
        id    => 3,
        short => 4,
        long  => 5,
    );

    if ( $opts{format} ) {
        if ( !$formats{ $opts{format} } ) {
            return undef;
        }

        if ( $opts{format} eq 'short' ) {
            return $self->short_string();
        }
        elsif ( $opts{format} eq 'long' ) {
            return $self->long_string();
        }
        elsif ( $opts{format} eq 'octal' ) {
            return hexstoocts( $self->{hex_string} );
        }
        elsif ( $opts{format} eq 'id' ) {
            return $self->id();
        }
    }

    return $self->{hex_string};
}

#
# Convert from octal string to hex string
#
sub octstohexs {
    my $octs = shift;
    my $ret  = '';      # Return string

    while ( $octs ne '' ) {

        # Look for octal escape seq at start of string.  Remove it
        # into $1
        if ( $octs =~ s/^\\([0-9]{3})// ) {

            # convert octal seq to number and write it as a hex number
            $ret .= sprintf( '%02x', oct($1) );
        }
        else {

            # Not octal escape sequence, so must be printable
            # character. Use the ord() operator to get the equivalent
            # value
            $octs =~ s/.//;
            $ret .= sprintf( '%02x', ord($&) );
        }
    }
    $ret = lc($ret);    # To lowercase
    return $ret;
}

#
# Convert from hex string to octal string.
#
# The hex string is assumed to be in format 000300010002FCA5DC1C.
#
# The octal string is a string of octal escapes and printable
# characters, e.g.  "\000\001\000\001\034b*tRT\000\000\001\002"
#
sub hexstoocts {
    my $hex_string = shift;
    my $ret        = '';      # Return string
    my $num;
    my @hex_array = unpack( '(A2)*', $hex_string );

    foreach (@hex_array) {

        # Convert hex string to number
        $num = hex($_);

        # If number is a printable ascii character then add that
        # to the output string, else add an octal escape sequence
        if ( $num > 32 and $num < 127 ) {
            $ret .= chr($num);
        }
        else {
            $ret .= sprintf( "\\%03o", $num );
        }
    }
    return $ret;
}

1;

__END__

=head1 NAME

DHCPv6Duid - DHCPv6 Unique Identifier

=head1 SYNOPSIS

    use Vyatta::DHCPv6Duid;

=head1 DESCRIPTION

DHCPv6Duid is a Perl module to parse and display DHCPv6 unique
identifiers.

=head2 DHCPv6Duid Object

    use Vyatta::DHCPv6Duid;
    my $duid = Vyatta::DHCPv6Duid->new($duid_string);

where $duid_string can be one of the following formats:

   00:01:00:01:1c:62:2A:74:52:54:00:00:01:02
   0:1:0:1:1c:62:2A:74:52:54:0:0:1:2
   \000\001\000\001\034b*tRT\000\000\001\002
   000300010002FCA5DC1C
   00-03-00-01-00-02-FC-A5-DC-1C
   0-3-0-1-0-2-FC-A5-DC-1C

=head1 METHODS

=head2 print

    $duid->print(format => 'hex');

Format specifiers:

    hex   - 000300010002FCA5DC1C
    octal - \000\001\000\001\034b*tRT\000\000\001\002
    id    - 00:03:00:01:00:02:FC:A5:DC:1C
    short - LL_TIME-Ethernet(1)-0x1c6f3043-52:54:00:f6:d7:11
    long  - 

=head2 link_layer_address

Returns a link-layer address string in hex if this DUID type includes
a link-layer address.

If the hardware type is ethernet then the 'ethernet_mac' format
specifier allows the link layer address string to be returned as a
colon-separated mac address.

    $duid->link_layer_address(format => 'ethernet_mac');

=head1 COPYRIGHT

Copyright (c) 2015, Brocade Comunications Systems, Inc.

=head1 AUTHOR INFORMATION

DHCPv6DUID was created by:
    Ian Wilson
    iwilson@brocade.com
