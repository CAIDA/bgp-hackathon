#!/usr/bin/perl

package Net::BGP::Update;
use Socket qw(PF_INET SOCK_STREAM pack_sockaddr_in inet_pton);
use bytes;

use strict;
use vars qw(
    $VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS
    @BGP_PATH_ATTR_FLAGS
);

## Inheritance and Versioning ##

use Net::BGP::NLRI qw( :origin );

@ISA     = qw( Exporter Net::BGP::NLRI );
$VERSION = '0.16';

my %Seen_Prefix = ();

## Module Imports ##

use Carp;
use IO::Socket;
use Net::BGP::Notification qw( :errors );

## General Definitions ##

sub TRUE  { 1 }
sub FALSE { 0 }

## BGP Path Attribute Type Enumerations ##

sub BGP_PATH_ATTR_ORIGIN           { 1 }
sub BGP_PATH_ATTR_AS_PATH          { 2 }
sub BGP_PATH_ATTR_NEXT_HOP         { 3 }
sub BGP_PATH_ATTR_MULTI_EXIT_DISC  { 4 }
sub BGP_PATH_ATTR_LOCAL_PREF       { 5 }
sub BGP_PATH_ATTR_ATOMIC_AGGREGATE { 6 }
sub BGP_PATH_ATTR_AGGREGATOR       { 7 }
sub BGP_PATH_ATTR_COMMUNITIES      { 8 }
sub BGP_PATH_ATTR_MP_REACH_NLRI    { 14 }
sub BGP_PATH_ATTR_AS4_PATH         { 17 }
sub BGP_PATH_ATTR_AS4_AGGREGATOR   { 18 }

## BGP Path Attribute Flag Octets ##

# This is the expected bits to be set in the flags section.
# Note that the PARTIAL is ignored where the flags indicate
# OPTIONAL + TRANSITIVE, because this can be set to 1 when
# passing through a router that doesn't understand the
# meaning of the optional attribute.
@BGP_PATH_ATTR_FLAGS = (
    0x00, ## TODO: change to undef after warnings enabled
    0x40,
    0x40,
    0x40,
    0x80,
    0x40,
    0x40,
    0xC0,
    0xC0,
    0x00, ## TODO: change to undef after warnings enabled
    0x00, ## TODO: change to undef after warnings enabled
    0x00, ## TODO: change to undef after warnings enabled
    0x00, ## TODO: change to undef after warnings enabled
    0x00, ## TODO: change to undef after warnings enabled
    0x80, 
    0x00, ## TODO: change to undef after warnings enabled
    0x00, ## TODO: change to undef after warnings enabled
    0xC0, # AS4_PATH
    0xC0, # AS4_AGGREGATOR
);

## RFC 4271, sec 4.3
our $BGP_PATH_ATTR_FLAG_OPTIONAL   = 0x80;
our $BGP_PATH_ATTR_FLAG_TRANSITIVE = 0x40;
our $BGP_PATH_ATTR_FLAG_PARTIAL    = 0x20;
our $BGP_PATH_ATTR_FLAG_EXTLEN     = 0x10;
our $BGP_PATH_ATTR_FLAG_RESERVED   = 0x0F;

## Per RFC 4271, sec 5.
##
our @_BGP_MANDATORY_ATTRS = ( BGP_PATH_ATTR_ORIGIN,
                              BGP_PATH_ATTR_AS_PATH,
                              BGP_PATH_ATTR_NEXT_HOP );

## Export Tag Definitions ##

@EXPORT      = ();
@EXPORT_OK   = ();
%EXPORT_TAGS = (
    ALL    => [ @EXPORT, @EXPORT_OK ]
);

## Public Methods ##

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    if (ref $_[0] eq 'Net::BGP::NLRI')
     { # Construct from NLRI
       $proto = shift unless ref $proto;
       my $this = $proto->clone;
       bless($this,$class);
       $this->nlri(shift);
       $this->withdrawn(shift);
       return $this;
     };

    my ($arg, $value);
    my @super_arg;
    my %this_arg;
    $this_arg{_withdrawn} = [];
    $this_arg{_nlri} = [];
    $this_arg{_mp_reach_nlri} = [];

    while ( defined($arg = shift()) ) {        
$value = shift();
        if ( $arg =~ /^nlri/i ) {
            $this_arg{_nlri} = $value;
        }
        elsif ( $arg =~ /withdraw/i ) {
            $this_arg{_withdrawn} = $value;
        } elsif ( $arg =~ /mp_reach_nlri/i ) {
	   $this_arg{_mp_reach_nlri} = $value;	
	}
        else {
            push(@super_arg,$arg,$value);
        }
    }

    my $this = $class->SUPER::new(@super_arg);
    @{$this}{keys %this_arg} = values(%this_arg);

    bless($this, $class);

    return ( $this );
}

sub clone
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    $proto = shift unless ref $proto;

    my $clone = $class->SUPER::clone($proto);

    foreach my $key (qw(_nlri _withdrawn ))
     {
      $clone->{$key} = [ @{$proto->{$key}} ];
     }

    return ( bless($clone, $class) );
}

sub nlri
{
    my $this = shift();

    $this->{_nlri} = @_ ? shift() : $this->{_nlri};
    return ( $this->{_nlri} );
}

sub withdrawn
{
    my $this = shift();

    $this->{_withdrawn} = @_ ? shift() : $this->{_withdrawn};
    return ( $this->{_withdrawn} );
}

sub ashash
{
    my $this = shift();

    my (%res,$nlri);

    $nlri = clone Net::BGP::NLRI($this) if defined($this->{_nlri});

    foreach my $prefix (@{$this->{_nlri}})
     {
      $res{$prefix} = $nlri;
     };

    foreach my $prefix (@{$this->withdrawn})
     {
      $res{$prefix} = undef;
     };

    return \%res;
}

## Private Methods ##

sub _new_from_msg
{
    my ($class, $buffer, $options) = @_;
    
    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    my $this = $class->new();

    $this->_decode_message($buffer, $options);

    return $this;
}

sub _encode_attr
{
    my ($this, $type, $data) = @_;
    my $buffer = '';

    my $flag = $BGP_PATH_ATTR_FLAGS[$type];
    my $len_format = 'C';

    my $len = length($data);
    if ($len > 255)
    {
        $flag |= $BGP_PATH_ATTR_FLAG_EXTLEN;
        $len_format = 'n';
    }

    $buffer .= pack('CC', $flag, $type);
    $buffer .= pack($len_format, $len);
    $buffer .= $data;

    return ( $buffer );
}

sub _decode_message
{
    my ($this, $buffer, $options) = @_;
    
    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    my $offset = 0;
    my $length;

    # decode the Withdrawn Routes field
    $length = unpack('n', substr($buffer, $offset, 2));
    $offset += 2;

    if ( $length > (length($buffer) - $offset) ) {
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_MALFORMED_ATTR_LIST
        );
    }

    $this->_decode_withdrawn(substr($buffer, $offset, $length));
    $offset += $length;

    # decode the Path Attributes field
    $length = unpack('n', substr($buffer, $offset, 2));
    $offset += 2;

    if ( $length > (length($buffer) - $offset) ) {
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_MALFORMED_ATTR_LIST
        );
    }

    return if $length == 0;    # withdrawn routes only

    $this->_decode_path_attributes(
        substr($buffer, $offset, $length),
        $options
    );

    $offset += $length;

    # decode the Network Layer Reachability Information field
    $this->_decode_nlri(substr($buffer, $offset));
}

sub _decode_origin
{
    my ($this, $buffer) = @_;

    $this->{_origin} = unpack('C', $buffer);
    $this->{_attr_mask}->[BGP_PATH_ATTR_ORIGIN] ++;

    return ( undef );
}

sub _decode_as_path
{
    my ($this, $buffer, $options) = @_;

    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    $this->{_as_path_raw} = $buffer;

    my $as4path = '';
    if ( exists $this->{_as4_path_raw} ) {
        $as4path = $this->{_as4_path_raw};
    }

    my $path = Net::BGP::ASPath->_new_from_msg(
            $buffer,
            $as4path,
            $options
    );

    $this->{_as_path} = $path;
    $this->{_attr_mask}->[BGP_PATH_ATTR_AS_PATH] ++;

    return ( undef );
}

# We don't decode the AS4 path, we just stick it in this variable.  That
# said, if we have already come across the AS_PATH (non AS4), we handle it.
sub _decode_as4_path
{
    my ($this, $buffer) = @_;

    $this->{_as4_path_raw} = $buffer;
    $this->{_attr_mask}->[BGP_PATH_ATTR_AS4_PATH] ++;

    # If we've already decoded the regular AS path, we need to reprocess
    # it now that we have an AS4_PATH.
    if ( defined $this->{_as_path_raw} ) {
        # We decrement the ref count for the AS_PATH (16 bit) because
        # this will otherwise trigger an error for having 2 AS_PATH
        # attributes, when it's really we just called it twice.
        $this->{_attr_mask}->[BGP_PATH_ATTR_AS_PATH] --;
        $this->_decode_as_path( $this->{_as_path_raw} );
    }

    return ( undef );
}

sub _decode_next_hop
{
    my ($this, $buffer) = @_;
    my ($data);

    if ( length($buffer) != 0x04 ) {
        $data = $this->_encode_attr(BGP_PATH_ATTR_NEXT_HOP, $buffer);
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_LENGTH,
            ErrorData    => $data
        );
    }

    # TODO: check if _next_hop is a valid IP host address
    $this->{_next_hop} = inet_ntoa($buffer);
    $this->{_attr_mask}->[BGP_PATH_ATTR_NEXT_HOP] ++;

    return ( undef );
}

sub _decode_med
{
    my ($this, $buffer) = @_;
    my ($data);

    if ( length($buffer) != 0x04 ) {
        $data = $this->_encode_attr(BGP_PATH_ATTR_MULTI_EXIT_DISC, $buffer);
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_LENGTH,
            ErrorData    => $data
        );
    }

    $this->{_med} = unpack('N', $buffer);
    $this->{_attr_mask}->[BGP_PATH_ATTR_MULTI_EXIT_DISC] ++;

    return ( undef );
}

sub _decode_local_pref
{
    my ($this, $buffer) = @_;
    my ($data);

    if ( length($buffer) != 0x04 ) {
        $data = $this->_encode_attr(BGP_PATH_ATTR_LOCAL_PREF, $buffer);
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_LENGTH,
            ErrorData    => $data
        );
    }

    $this->{_local_pref} = unpack('N', $buffer);
    $this->{_attr_mask}->[BGP_PATH_ATTR_LOCAL_PREF] ++;

    return ( undef );
}

sub _decode_atomic_aggregate
{
    my ($this, $buffer) = @_;
    my ($data);

    if ( length($buffer) ) {
        $data = $this->_encode_attr(BGP_PATH_ATTR_ATOMIC_AGGREGATE, $buffer);
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_LENGTH,
            ErrorData    => $data
        );
    }

    $this->{_atomic_agg} = TRUE;
    $this->{_attr_mask}->[BGP_PATH_ATTR_ATOMIC_AGGREGATE] ++;

    return ( undef );
}

sub _decode_aggregator
{
    my ($this, $buffer, $options) = @_;

    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    my ($data);

    if ($options->{as4}) {
        if ( length($buffer) != 0x08 ) {
            $data = $this->_encode_attr(BGP_PATH_ATTR_AGGREGATOR, $buffer);
            Net::BGP::Notification->throw(
                ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
                ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_LENGTH,
                ErrorData    => $data
            );
        }

        $this->{_aggregator}->[0] = unpack('N', substr($buffer, 0, 4));
        $this->{_aggregator}->[1] = inet_ntoa(substr($buffer, 4, 4));
    } else {
        if ( length($buffer) != 0x06 ) {
            $data = $this->_encode_attr(BGP_PATH_ATTR_AGGREGATOR, $buffer);
            Net::BGP::Notification->throw(
                ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
                ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_LENGTH,
                ErrorData    => $data
            );
        }

        $this->{_aggregator}->[0] = unpack('n', substr($buffer, 0, 2));
        $this->{_aggregator}->[1] = inet_ntoa(substr($buffer, 2, 4));
    }
    $this->{_attr_mask}->[BGP_PATH_ATTR_AGGREGATOR] ++;

    if ( $options->{as4} ) { return ( undef ); }
    if (!exists($this->{_as4_aggregator}->[0])) { return ( undef ); }

    if ($this->{_aggregator}->[0] != 23456) {
        # Disregard _as4_aggregator if not AS_TRANS, per RFC4893 4.2.3
        return ( undef );
    }

    @{ $this->{_aggregator} } = @{ $this->{_as4_aggregator} };

    return ( undef );
}

sub _decode_as4_aggregator
{
    my ($this, $buffer, $options) = @_;
    
    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    my ($data);

    if ( length($buffer) != 0x08 ) {
        $data = $this->_encode_attr(BGP_PATH_ATTR_AS4_AGGREGATOR, $buffer);
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_LENGTH,
            ErrorData    => $data
        );
    }

    $this->{_as4_aggregator}->[0] = unpack('N', substr($buffer, 0, 4));
    $this->{_as4_aggregator}->[1] = inet_ntoa(substr($buffer, 4, 4));
    $this->{_attr_mask}->[BGP_PATH_ATTR_AS4_AGGREGATOR] ++;
    
    if ( $options->{as4} ) { return ( undef ); }
    if (!exists($this->{_aggregator}->[0])) { return ( undef ); }

    if ($this->{_aggregator}->[0] != 23456) {
        # Disregard _as4_aggregator if not AS_TRANS, per RFC4893 4.2.3
        return ( undef );
    }

    @{ $this->{_aggregator} } = @{ $this->{_as4_aggregator} };

    return ( undef );
}

sub _decode_communities
{
    my ($this, $buffer) = @_;
    my ($as, $val, $ii, $offset, $count);
    my ($data);

    if ( length($buffer) % 0x04 ) {
        $data = $this->_encode_attr(BGP_PATH_ATTR_COMMUNITIES, $buffer);
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_LENGTH,
            ErrorData    => $data
        );
    }

    $offset = 0;
    $count = length($buffer) / 4;
    for ( $ii = 0; $ii < $count; $ii++ ) {
        $as  = unpack('n', substr($buffer, $offset, 2));
        $val = unpack('n', substr($buffer, $offset + 2, 2));
        push(@{$this->{_communities}}, join(":", $as, $val));
        $offset += 4;
    }

    $this->{_attr_mask}->[BGP_PATH_ATTR_COMMUNITIES] ++;

    return ( undef );
}

sub _decode_path_attributes
{
    my ($this, $buffer, $options) = @_;

    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    my ($offset, $data_length);
    my ($flags, $type, $length, $len_format, $len_bytes, $sub, $data);
    my ($error_data, $ii);
    my @decode_sub = (
        undef,                              # 0
        \&_decode_origin,                   # 1
        \&_decode_as_path,                  # 2
        \&_decode_next_hop,                 # 3
        \&_decode_med,                      # 4
        \&_decode_local_pref,               # 5
        \&_decode_atomic_aggregate,         # 6
        \&_decode_aggregator,               # 7
        \&_decode_communities,              # 8
        undef,                              # 9
        undef,                              # 10
        undef,                              # 11
        undef,                              # 12
        undef,                              # 13
        undef,                              # 14
        undef,                              # 15
        undef,                              # 16
        \&_decode_as4_path,                 # 17
        \&_decode_as4_aggregator,           # 18
    );

    $offset = 0;
    $data_length = length($buffer);

    while ( $data_length ) {
        $flags   = unpack('C', substr($buffer, $offset++, 1));
        $type    = unpack('C', substr($buffer, $offset++, 1));

        $len_format = 'C';
        $len_bytes  = 1;
        if ( $flags & $BGP_PATH_ATTR_FLAG_EXTLEN ) {
            $len_format = 'n';
            $len_bytes  = 2;
        }

        $length  = unpack($len_format, substr($buffer, $offset, $len_bytes));
        $offset += $len_bytes;

        if ( $length > ($data_length - ($len_bytes + 2)) ) {
            $data = substr($buffer, $offset - $len_bytes - 2, $length + $len_bytes + 2);
            Net::BGP::Notification->throw(
                ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
                ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_LENGTH,
                ErrorData    => $error_data
            );
        }

        ## do we know how to decode this attribute?
        if (defined $decode_sub[$type])
        {
            $error_data = substr(
                    $buffer,
                    $offset - $len_bytes - 2,
                    $length + $len_bytes + 2

            );

            my $flagmasked = $flags;
            $flagmasked &= ~$BGP_PATH_ATTR_FLAG_EXTLEN;
            $flagmasked &= ~$BGP_PATH_ATTR_FLAG_RESERVED;

            if ( $BGP_PATH_ATTR_FLAGS[$type] != $flagmasked ) {

                # See RFC4271 Section 5
                if (   ( $flagmasked & $BGP_PATH_ATTR_FLAG_OPTIONAL )
                    && ( $flagmasked & $BGP_PATH_ATTR_FLAG_TRANSITIVE )
                    && ( $BGP_PATH_ATTR_FLAGS[$type] ==
                        ($flagmasked & ~$BGP_PATH_ATTR_FLAG_PARTIAL)
                       )
                ) {
                    # In this case, the flags only differ in the partial bit
                    # So it's actually okay.
                } else {
                    Net::BGP::Notification->throw(
                        ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
                        ErrorSubCode => BGP_ERROR_SUBCODE_BAD_ATTR_FLAGS,
                        ErrorData    => $error_data
                    );
                }

                # Watch out for the do-nothing case in the "if" statement
                # above.
            }

            $sub = $decode_sub[$type];
            $this->$sub(substr($buffer, $offset, $length), $options);
        }

        $offset += $length;
        $data_length -= ($length + $len_bytes + 2);
    }

    ## Check for missing mandatory well-known attributes XXX
    ##
    #for my $attr (@_BGP_MANDATORY_ATTRS)
    #{
    #    $this->{_attr_mask}->[$attr]
    #        or Net::BGP::Notification->throw(
    #            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
    #            ErrorSubCode => BGP_ERROR_SUBCODE_MISSING_WELL_KNOWN_ATTR,
    #            ErrorData    => pack('C', $attr)
    #        );
    #}

    ## Check for repeated attributes, which violates RFC 4271, sec 5.
    ##
    if ( grep { defined $_ and $_ > 1 } @{$this->{_attr_mask}||[]} )
    {
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_MALFORMED_ATTR_LIST
        );
    }
}

sub _decode_prefix_list
{
    my ($this, $buffer) = @_;
    my ($offset, $data_length);
    my ($prefix, $prefix_bits, $prefix_bytes, $ii, @prefix_list);

    $offset = 0;
    $data_length = length($buffer);

    while ( $data_length ) {
        $prefix_bits = unpack('C', substr($buffer, $offset++, 1));
        $prefix_bytes = int($prefix_bits / 8) + (($prefix_bits % 8) ? 1 : 0);

        if ( $prefix_bytes > ($data_length - 1)) {
            return ( FALSE );
        }

        $prefix = 0;
        for ( $ii = 0; $ii < $prefix_bytes; $ii++ ) {
            $prefix |= (unpack('C', substr($buffer, $offset++, 1)) << (24 - ($ii * 8)));
        }

        $prefix = pack('N', $prefix);
        push(@prefix_list, inet_ntoa($prefix) . "/" . $prefix_bits);
        $data_length -= ($prefix_bytes + 1);
    }

    return ( TRUE, @prefix_list );
}

sub _decode_withdrawn
{
    my ($this, $buffer) = @_;
    my ($result, @prefix_list);

    ($result, @prefix_list) = $this->_decode_prefix_list($buffer);
    if ( ! $result ) {
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_MALFORMED_ATTR_LIST
        );
    }

    push(@{$this->{_withdrawn}}, @prefix_list);
}

sub _decode_nlri
{
    my ($this, $buffer) = @_;
    my ($result, @prefix_list);

    ($result, @prefix_list) = $this->_decode_prefix_list($buffer);
    if ( ! $result ) {
        Net::BGP::Notification->throw(
            ErrorCode    => BGP_ERROR_CODE_UPDATE_MESSAGE,
            ErrorSubCode => BGP_ERROR_SUBCODE_BAD_NLRI
        );
    }

    push(@{$this->{_nlri}}, @prefix_list);
}

sub _encode_message
{
    my ($this, $options) = @_;

    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    my ($buffer, $withdrawn, $path_attr, $nlri);

    # encode the Withdrawn Routes field
    $withdrawn = $this->_encode_prefix_list($this->{_withdrawn});
    $buffer = pack('n', length($withdrawn)) . $withdrawn;

    # encode the Path Attributes field
    $path_attr = $this->_encode_path_attributes( $options );
    $buffer .= (pack('n', length($path_attr)) . $path_attr);

    # encode the Network Layer Reachability Information field
    $buffer .= $this->_encode_prefix_list($this->{_nlri});

    return ( $buffer );
}

sub _encode_prefix
{
    my $prefix = shift();
    my ($buffer, $length, @octets);

    ($prefix, $length) = split('/', $prefix);

    if (!exists($Seen_Prefix{$prefix})) {
	$Seen_Prefix{$prefix} = 0;
    }
    $Seen_Prefix{$prefix}++;
    $buffer = pack('N', $Seen_Prefix{$prefix}); # identifier XXX do that only if add path is enabled
    $buffer .= pack('C', $length);

    @octets = split(/\./, $prefix);
    while ( $length > 0 ) {
	
        $buffer .= pack('C', shift(@octets));
        $length -= 8;
    }

    return ( $buffer );
}

sub _encode_prefix_list
{
    my ($this, $prefix_list) = @_;
    my ($prefix, $buffer);

    $buffer = '';
    foreach $prefix ( @{$prefix_list} ) {
        $buffer .= _encode_prefix($prefix);
    }

    return ( $buffer );
}

sub _encode_origin
{
    my $this = shift();

    $this->_encode_attr(BGP_PATH_ATTR_ORIGIN,
                        pack('C', $this->{_origin}));
}

sub _encode_as_path
{
    my ($this, $options) = @_;

    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    my ($as_buffer, $as4_buffer) = $this->{_as_path}->_encode($options);

    my $output;

    $output = $this->_encode_attr(BGP_PATH_ATTR_AS_PATH, $as_buffer);

    if (defined $as4_buffer) {
        $output .= $this->_encode_attr(BGP_PATH_ATTR_AS4_PATH, $as4_buffer);
    }

    return $output;
}

sub _encode_next_hop
{
    	
    my $this = shift();
    if ($this->{_next_hop} !~ /\:/) {  #XXX
    $this->_encode_attr(BGP_PATH_ATTR_NEXT_HOP,
                        inet_aton($this->{_next_hop}));
	}
}

sub _encode_med
{
    my $this = shift();
    $this->_encode_attr(BGP_PATH_ATTR_MULTI_EXIT_DISC,
                        pack('N', $this->{_med}));
}

sub _encode_local_pref
{
    my $this = shift();
    $this->_encode_attr(BGP_PATH_ATTR_LOCAL_PREF,
                        pack('N', $this->{_local_pref}));
}

sub _encode_atomic_aggregate
{
    my $this = shift();
    $this->_encode_attr(BGP_PATH_ATTR_ATOMIC_AGGREGATE);
}

sub _encode_aggregator
{
    my ($this, $options) = @_;

    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    my ($aggr, $ret);

    if ($options->{as4}) {
        $aggr = pack('N', $this->{_aggregator}->[0]) .
            inet_aton($this->{_aggregator}->[1]);

        $ret = $this->_encode_attr(BGP_PATH_ATTR_AGGREGATOR, $aggr);
    } elsif ($aggr <= 65535) {
        $aggr = pack('n', $this->{_aggregator}->[0]) .
            inet_aton($this->{_aggregator}->[1]);

        $ret = $this->_encode_attr(BGP_PATH_ATTR_AGGREGATOR, $aggr);
    } else {
        $aggr = pack('n', 23456) .
            inet_aton($this->{_aggregator}->[1]);
        
        $ret = $this->_encode_attr(BGP_PATH_ATTR_AGGREGATOR, $aggr);
    
        $aggr = pack('N', $this->{_aggregator}->[0]) .
            inet_aton($this->{_aggregator}->[1]);

        $ret .= $this->_encode_attr(BGP_PATH_ATTR_AS4_AGGREGATOR, $aggr);
    }

    return $ret;
}

sub _encode_communities
{
    my $this = shift();
    my ($as, $val, $community, @communities);
    my ($buffer, $community_buffer);

    @communities = @{$this->{_communities}};
    foreach $community ( @communities ) {
        ($as, $val) = split(/\:/, $community);
        $community_buffer .= pack('nn', $as, $val);
    }

    $this->_encode_attr(BGP_PATH_ATTR_COMMUNITIES, $community_buffer);
}

sub _encode_mp_reach_nlri
{

    my $this = shift(); 
    my $mp_reach_nlri_buffer;
    my @prefixes = @{$this->{_mp_reach_nlri}};
    my $next_hop = $this->{_next_hop};
    
    #print "+++";
    #my @res =  unpack('CCCCCCCCCCCCCCCC', inet_pton(AF_INET6, $next_hop));
    #print $res[15];
    #print "---\n";
    
    $mp_reach_nlri_buffer .= pack('n', 2); # AFI IPv6 on two bytes
    $mp_reach_nlri_buffer .= pack('C', 1); # SAFI UNICAST
    $mp_reach_nlri_buffer .= pack('C', 16); # length of next hop fixed to 16 bytes
    $mp_reach_nlri_buffer .= inet_pton(AF_INET6, $next_hop);
    $mp_reach_nlri_buffer .= pack('C', 0); # reserved
    
    foreach my $prefix (@prefixes) {
    	
	my ($prefix_value, $prefix_len_in_bits) = split /\//, $prefix;
	
	#XXX do that only if add path is enabled!
	if (!exists($Seen_Prefix{$prefix})) {
		$Seen_Prefix{$prefix} = 0;
        }
        $Seen_Prefix{$prefix}++;
        $mp_reach_nlri_buffer .= pack('N', $Seen_Prefix{$prefix}); # identifier
	#XXX
	
	$mp_reach_nlri_buffer .= pack('C', $prefix_len_in_bits); # length
	my $prefix_len_in_bytes = int($prefix_len_in_bits/8);
	if ($prefix_len_in_bits % 8 != 0) {
		$prefix_len_in_bytes++;
	}

	my @res = unpack('CCCCCCCCCCCCCCCC', inet_pton(AF_INET6, $prefix_value));
	for (my $i = 0; $i < $prefix_len_in_bytes; $i++) { # only put the required bytes into the buffer
		$mp_reach_nlri_buffer .= pack('C', $res[$i]);
	}
    }
    
    $this->_encode_attr(BGP_PATH_ATTR_MP_REACH_NLRI, $mp_reach_nlri_buffer);
}

sub _encode_path_attributes
{
	
    my ($this, $options) = @_;
	#foreach my $opt (keys $options) {
	#	print "${$options}{$opt}\n";
	#}
    if (!defined($options)) { $options = {}; }
    $options->{as4} ||= 0;

    my $buffer;

    $buffer = '';

    # do not encode path attributes if no NLRI is present
    unless (
    	((defined $this->{_nlri}) && scalar(@{$this->{_nlri}})) || 
    	((defined $this->{_mp_reach_nlri}) && scalar(@{$this->{_mp_reach_nlri}}))
	) {
        return ( $buffer );
    }

    # encode the ORIGIN path attribute
    if ( ! defined($this->{_origin}) ) {
        carp "mandatory path attribute ORIGIN not defined\n";
    }
    $buffer = $this->_encode_origin();

    # encode the AS_PATH path attribute
    if ( ! defined($this->{_as_path}) ) {
        carp "mandatory path attribute AS_PATH not defined\n";
    }
    $buffer .= $this->_encode_as_path($options);

    # encode the NEXT_HOP path attribute
    if ( ! defined($this->{_next_hop}) ) {
        carp "mandatory path attribute NEXT_HOP not defined\n";
    }
    $buffer .= $this->_encode_next_hop();

    # encode the MULTI_EXIT_DISC path attribute
    if ( defined($this->{_med}) ) {
        $buffer .= $this->_encode_med();
    }

    # encode the LOCAL_PREF path attribute
    if ( defined($this->{_local_pref}) ) {
        $buffer .= $this->_encode_local_pref();
    }

    # encode the ATOMIC_AGGREGATE path attribute
    if ( defined($this->{_atomic_agg}) ) {
        $buffer .= $this->_encode_atomic_aggregate();
    }

    # encode the AGGREGATOR path attribute
    if ( scalar(@{$this->{_aggregator}}) ) {
        $buffer .= $this->_encode_aggregator($options);
    }

    # encode the COMMUNITIES path attribute
    if ( scalar(@{$this->{_communities}}) ) {
        $buffer .= $this->_encode_communities();
    }

    # encode the MP_REACH path attribute
    if ( defined($this->{_mp_reach_nlri})) {
        $buffer .= $this->_encode_mp_reach_nlri();
    }

    return ( $buffer );
}

## POD ##

=pod

=head1 NAME

Net::BGP::Update - Class encapsulating BGP-4 UPDATE message

=head1 SYNOPSIS

    use Net::BGP::Update qw( :origin );

    # Constructor
    $update = Net::BGP::Update->new(
        NLRI            => [ qw( 10/8 172.168/16 ) ],
        Withdraw        => [ qw( 192.168.1/24 172.10/16 192.168.2.1/32 ) ],
	# For Net::BGP::NLRI
        Aggregator      => [ 64512, '10.0.0.1' ],
        AsPath          => [ 64512, 64513, 64514 ],
        AtomicAggregate => 1,
        Communities     => [ qw( 64512:10000 64512:10001 ) ],
        LocalPref       => 100,
        MED             => 200,
        NextHop         => '10.0.0.1',
        Origin          => INCOMPLETE,
    );

    # Construction from a NLRI object:
    $nlri = Net::BGP::NLRI->new( ... );
    $update = Net::BGP::Update->new($nlri,$nlri_ref,$withdrawn_ref);

    # Object Copy
    $clone = $update->clone();

    # Accessor Methods
    $nlri_ref         = $update->nlri($nlri_ref);
    $withdrawn_ref    = $update->withdrawn($withdrawn_ref);
    $prefix_hash_ref  = $update->ashash;

    # Comparison
    if ($update1 eq $update2) { ... }
    if ($update1 ne $update2) { ... }

=head1 DESCRIPTION

This module encapsulates the data contained in a BGP-4 UPDATE message.
It provides a constructor, and accessor methods for each of the
message fields and well-known path attributes of an UPDATE. Whenever
a B<Net::BGP::Peer> sends an UPDATE message to its peer, it does so
by passing a B<Net::BGP::Update> object to the peer object's I<update()>
method. Similarly, when the peer receives an UPDATE message from its
peer, the UPDATE callback is called and passed a reference to a
B<Net::BGP::Update> object. The callback function can then examine
the UPDATE message fields by means of the accessor methods.

=head1 CONSTRUCTOR

I<new()> - create a new Net::BGP::Update object

    $update = Net::BGP::Update->new(
        NLRI            => [ qw( 10/8 172.168/16 ) ],
        Withdraw        => [ qw( 192.168.1/24 172.10/16 192.168.2.1/32 ) ],
	# For Net::BGP::NLRI
        Aggregator      => [ 64512, '10.0.0.1' ],
        AsPath          => [ 64512, 64513, 64514 ],
        AtomicAggregate => 1,
        Communities     => [ qw( 64512:10000 64512:10001 ) ],
        LocalPref       => 100,
        MED             => 200,
        NextHop         => '10.0.0.1',
        Origin          => INCOMPLETE,
    );

This is the constructor for Net::BGP::Update objects. It returns a
reference to the newly created object. The following named parameters may
be passed to the constructor. See RFC 1771 for the semantics of each
path attribute.

An alternative is to construct an object from a Net::BGP::NLRI object:

    $nlri = Net::BGP::NLRI->new( ... );
    $nlri_ref = [ qw( 10/8 172.168/16 ) ];
    $withdrawn_ref = [ qw( 192.168.1/24 172.10/16 192.168.2.1/32 ) ];
    $update = Net::BGP::Update->new($nlri,$nlri_ref,$withdrawn_ref);

The NLRI object will not be modified in any way.

=head2 NLRI

This parameter corresponds to the Network Layer Reachability Information (NLRI)
field of an UPDATE message. It represents the route(s) being advertised in this
particular UPDATE. It is expressed as an array reference of route prefixes which
are encoded in a special format as perl strings: XXX.XXX.XXX.XXX/XX. The part
preceding the slash is a dotted-decimal notation IP prefix. Only as many octets
as are significant according to the mask need to be specified. The part following
the slash is the mask which is an integer in the range [0,32] which indicates how
many bits are significant in the prefix. At least one of either the NLRI or Withdraw
parameters is mandatory and must always be provided to the constructor.

=head2 Withdraw

This parameter corresponds to the Withdrawn Routes field of an UPDATE message. It
represents route(s) advertised by a previous UPDATE message which are now being
withdrawn by this UPDATE. It is expressed in the same way as the NLRI parameter.
At least one of either the NLRI or Withdraw parameters is mandatory and must
always be provided to the constructor.

=head1 OBJECT COPY

I<clone()> - clone a Net::BGP::Update object

    $clone = $update->clone();

This method creates an exact copy of the Net::BGP::Update object, with Withdrawn
Routes, Path Attributes, and NLRI fields matching those of the original object.
This is useful for propagating a modified UPDATE message when the original object
needs to remain unchanged.

=head1 ACCESSOR METHODS

I<nlri()>

I<withdrawn()>

These accessor methods return the value(s) of the associated UPDATE message field
if called with no arguments. If called with arguments, they set
the associated field. The representation of parameters and return values is the
same as described for the corresponding named constructor parameters above.

I<ashash()>

This method returns a hash reference index on the prefixes in found in the nlri
and withdrawn fields.  Withdrawn networks has undefined as value, while nlri
prefixes all has the same reference to a Net::BGP::NLRI object matching the
Update object self. 

=head1 EXPORTS

The module does not export anything.

=head1 SEE ALSO

B<RFC 1771>, B<RFC 1997>, B<Net::BGP>, B<Net::BGP::Process>, B<Net::BGP::Peer>,
B<Net::BGP::Notification>, B<Net::BGP::NLRI>

=head1 AUTHOR

Stephen J. Scheck <code@neurosphere.com>

=cut

## End Package Net::BGP::Update ##

1;
