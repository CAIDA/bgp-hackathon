#!/usr/bin/perl

package Net::BGP::Peer;
use bytes;

use strict;
use vars qw(
    $VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS @BGP @GENERIC
    @BGP_EVENT_MESSAGE_MAP @BGP_EVENTS @BGP_FSM @BGP_STATES
);

## Inheritance and Versioning ##

@ISA     = qw( Exporter );
$VERSION = '0.16';

## General Definitions ##

sub TRUE  { 1 }
sub FALSE { 0 }

## BGP Network Constants ##

sub BGP_PORT      { 179 }
sub BGP_VERSION_4 {   4 }

## Export Tag Definitions ##

@BGP         = qw( BGP_PORT BGP_VERSION_4 );
@GENERIC     = qw( TRUE FALSE dump_hex );
@EXPORT      = ();
@EXPORT_OK   = ( @BGP, @GENERIC );
%EXPORT_TAGS = (
    bgp      => [ @BGP ],
    generic  => [ @GENERIC ],
    ALL      => [ @EXPORT, @EXPORT_OK ]
);

## Module Imports ##

use Scalar::Util qw( weaken );
use Exporter;
use IO::Socket;
use Carp;
use Carp qw(cluck);
use Net::BGP::Notification qw( :errors );
use Net::BGP::Refresh;
use Net::BGP::Update;
use Net::BGP::Transport;

## Global private variables ##

my %knownpeers;

## Generic Subroutines ##

# This subroutine was snicked from David Town's excellent Net::SNMP
# module and renamed as dump_hex(). Removed class dependence and made
# into standalone subroutine.

sub dump_hex
{
   my $data = shift();
   my ($length, $offset, $line, $hex) = (0, 0, '', '');
   my $string;

   $string = '';
   $length = length($data);

   while ($length > 0) {
      if ($length >= 16) {
         $line = substr($data, $offset, 16);
      } else {
         $line = substr($data, $offset, $length);
      }
      $hex  = unpack('H*', $line);
      $hex .= ' ' x (32 - length($hex));
      $hex  = sprintf("%s %s %s %s  " x 4, unpack('a2' x 16, $hex));
      $line =~ s/[\x00-\x1f\x7f-\xff]/./g;
      $string .= sprintf("[%03d]  %s %s\n", $offset, uc($hex), $line);
      $offset += 16;
      $length -= 16;
   }

   return ( $string );
}

## Public Class Methods ##

sub new
{
    my $class = shift();
    my ($arg, $value);

    my $this = {
        _bgp_version           => BGP_VERSION_4,
        _local_id              => undef,
        _peer_id               => undef,
        _peer_port             => BGP_PORT,
        _local_as              => 0,
        _peer_as               => 0,
        _user_timers           => {},
        _transport             => undef,
        _listen                => TRUE,
        _passive               => FALSE,
        _announce_refresh      => FALSE,
        _support_capabilities  => TRUE,
        _support_mbgp          => TRUE,
        _support_as4           => FALSE,
        _open_callback         => undef,
        _established_callback  => undef,
        _keepalive_callback    => undef,
        _update_callback       => undef,
        _refresh_callback      => undef,
        _reset_callback        => undef,
        _notification_callback => undef,
        _error_callback        => undef
    };

    bless($this, $class);

    my %transarg = ();
    while ( defined($arg = shift()) ) {
        $value = shift();

        if (( $arg =~ /^start$/i )
         || ( $arg =~ /^connectretrytime$/i )
         || ( $arg =~ /^keepalivetime$/i )
         || ( $arg =~ /^holdtime$/i )) {
            $transarg{$arg} = $value;
        }
        elsif ( $arg =~ /^thisid$/i ) {
            $this->{_local_id} = $value;
        }
        elsif ( $arg =~ /^thisas$/i ) {
            $this->{_local_as} = $value;
        }
        elsif ( $arg =~ /^peerid$/i ) {
            $this->{_peer_id} = $value;
        }
        elsif ( $arg =~ /^peeras$/i ) {
            $this->{_peer_as} = $value;
        }
        elsif ( $arg =~ /^peerport$/i ) {
            $this->{_peer_port} = $value;
        }
        elsif ( $arg =~ /^listen$/i ) {
            $this->{_listen} = $value;
        }
        elsif ( $arg =~ /^passive$/i ) {
            $this->{_passive} = $value;
        }
        elsif ( $arg =~ /^refreshcallback$/i ) {
            $this->{_refresh_callback} = $value;
        }
        elsif ( $arg =~ /^refresh$/i ) {
            warnings::warnif(
                'deprecated',
                'Refresh in is deprecated, use AnnounceRefresh instead'
            );
            $this->{_announce_refresh} = $value;
        }
        elsif ( $arg =~ /^announcerefresh$/i ) {
            $this->{_announce_refresh} = $value;
        }
        elsif ( $arg =~ /^supportcapabilities$/i ) {
            $this->{_support_capabilities} = $value;
        }
        elsif ( $arg =~ /^supportmbgp$/i ) {
            $this->{_support_mbgp} = $value;
        }
        elsif ( $arg =~ /^supportas4$/i ) {
            $this->{_support_as4} = $value;
        } 
        elsif ( $arg =~ /^supportadd_path$/i ) {
            $this->{_support_add_path} = $value;
        }
        elsif ( $arg =~ /^opencallback$/i ) {
            $this->{_open_callback} = $value;
        }
        elsif ( $arg =~ /^establishedcallback$/i ) {
            $this->{_established_callback} = $value;
        }
        elsif ( $arg =~ /^keepalivecallback$/i ) {
            $this->{_keepalive_callback} = $value;
        }
        elsif ( $arg =~ /^updatecallback$/i ) {
            $this->{_update_callback} = $value;
        }
        elsif ( $arg =~ /^resetcallback$/i ) {
            $this->{_reset_callback} = $value;
        }
        elsif ( $arg =~ /^notificationcallback$/i ) {
            $this->{_notification_callback} = $value;
        }
        elsif ( $arg =~ /^errorcallback$/i ) {
            $this->{_error_callback} = $value;
        }
        else {
            croak "unrecognized argument $arg\n";
        }
    }

    $transarg{parent} = $this;
    $this->{_transport} = Net::BGP::Transport->new(%transarg);

    weaken($knownpeers{$this} = $this);
    return ( $this );
}

sub renew
{
    my $proto = shift;
    my $class = ref $proto || $proto;
    my $name = shift;
    return $knownpeers{$name};
}

## Public Object Methods - Proxies for backward compatibility ##

sub start
{
	
    foreach my $trans (shift->transports)
     {
      $trans->start();
     };
}

sub stop
{
    foreach my $trans (shift->transports)
     {
      $trans->stop();
     };
}

sub version
{
    return shift->transport->version;
}

sub update
{
    return shift->transport->update(@_);
}

sub refresh
{
    return shift->transport->refresh(@_);
}

## Public Object Methods ##

sub transport
{
    my $this = shift();
    $this->{_transport} = shift if @_;
    return $this->{_transport};
}

sub transports
{
    my $this = shift();
    return ($this->transport) unless defined $this->transport->sibling;
    return ($this->transport,$this->transport->sibling);
}

sub this_id
{
    my $this = shift();
    return ( $this->{_local_id} );
}

sub this_as
{
    my $this = shift();
    return ( $this->{_local_as} );
}

sub this_can_refresh
{
    my $this = shift();
    return ( $this->{_announce_refresh} );
}

sub this_can_as4
{
    my $this = shift();
    return ( $this->{_support_as4} );
}

sub this_can_add_path
{
    my $this = shift();
    return ( $this->{_support_add_path} );
}

sub support_capabilities
{
    my $this = shift();
    return ( $this->{_support_capabilities} );
}

sub support_mbgp
{
    my $this = shift();
    return ( $this->{_support_mbgp} );
}

sub peer_id
{
    my $this = shift();
    return ( $this->{_peer_id} );
}

sub peer_as
{
    my $this = shift();
    return ( $this->{_peer_as} );
}

sub peer_port
{
    my $this = shift();
    return ( $this->{_peer_port} );
}

sub peer_can_as4
{
    my $this = shift();
    return $this->transport->can_as4;
}

sub peer_can_mbgp
{
    my $this = shift();
    return $this->transport->can_mbgp;
}

sub peer_can_refresh
{
    my $this = shift();
    return $this->transport->can_refresh;
}

sub is_listener
{
    my $this = shift();
    return ( $this->{_listen} );
}

sub is_passive
{
    my $this = shift();
    return ( $this->{_passive} );
}

sub is_established
{
    my $this = shift();
    return ( $this->transport->is_established );
}

sub set_open_callback
{
    my ($this, $callback) = @_;
    $this->{_open_callback} = $callback;
}

sub set_established_callback
{
    my ($this, $callback) = @_;
    $this->{_established_callback} = $callback;
}

sub set_keepalive_callback
{
    my ($this, $callback) = @_;
    $this->{_keepalive_callback} = $callback;
}

sub set_update_callback
{
    my ($this, $callback) = @_;
    $this->{_update_callback} = $callback;
}

sub set_refresh_callback
{
    my ($this, $callback) = @_;
    $this->{_refresh_callback} = $callback;
}

sub set_reset_callback
{
    my ($this, $callback) = @_;
    $this->{_reset_callback} = $callback;
}

sub set_notification_callback
{
    my ($this, $callback) = @_;
    $this->{_notification_callback} = $callback;
}

sub set_error_callback
{
    my ($this, $callback) = @_;
    $this->{_error_callback} = $callback;
}

sub add_timer
{
    my ($this, $callback, $timeout) = @_;
    my $timer;

    $timer = {
        _timer    => $timeout,
        _timeout  => $timeout,
        _callback => $callback,
    };

    $this->{_user_timers}->{$timer} = $timer;
}

sub remove_timer
{
    my ($this, $callback) = @_;
    my ($key, $timer);

    foreach $key ( keys(%{$this->{_user_timers}}) ) {
        $timer = $this->{_user_timers}->{$key};
        if ( $timer->{_callback} == $callback ) {
            delete $this->{_user_timers}->{$key};
        }
    }
}

sub asstring
{
    my $this = shift;

    my @l = map { defined $_ ? $_ : 'n/a'; } (
	$this->this_id, $this->this_as, 
	$this->peer_id, $this->peer_as);

    return $l[0] . ':' . $l[1] . '<=>' . $l[2] . ':' . $l[3];
}

## Overridable Methods ##

sub open_callback
{
    my $this = shift();

    if ( defined($this->{_open_callback}) ) {
        &{ $this->{_open_callback} }($this);
    }
}

sub established_callback
{
    my $this = shift();

    if ( defined($this->{_established_callback}) ) {
        &{ $this->{_established_callback} }($this);
    }
}

sub keepalive_callback
{
    my $this = shift();

    if ( defined($this->{_keepalive_callback}) ) {
        &{ $this->{_keepalive_callback} }($this);
    }
}

sub update_callback
{
    my ($this, $update) = @_;

    if ( defined($this->{_update_callback}) ) {
        &{ $this->{_update_callback} }($this, $update);
    }
}

sub refresh_callback
{
    my ($this,$refresh) = @_;

    if ( defined($this->{_refresh_callback}) ) {
        &{ $this->{_refresh_callback} }($this,$refresh);
    }
}

sub reset_callback
{
    my ($this,$refresh) = @_;

    if ( defined($this->{_reset_callback}) ) {
        &{ $this->{_reset_callback} }($this);
    }
}

sub notification_callback
{
    my ($this, $error) = @_;

    if ( defined($this->{_notification_callback}) ) {
        &{ $this->{_notification_callback} }($this, $error);
    }
}

sub error_callback
{
    my ($this, $error) = @_;

    if ( defined($this->{_error_callback}) ) {
        &{ $this->{_error_callback} }($this, $error);
    }
}

## Private Object Methods ##

sub _update_timers
{
    my ($this, $delta) = @_;

    # Proxy for transport timers
    my $min_time = $this->transport->_update_timers($delta);
 
    # Update user defined timers
    foreach my $key ( keys(%{$this->{_user_timers}}) ) {
        my $timer = $this->{_user_timers}->{$key};
        if ( defined($timer->{_timer}) ) {
            $timer->{_timer} -= $delta;

            if ( $timer->{_timer} <= 0 ) {
                $timer->{_timer} = $timer->{_timeout};
                &{ $timer->{_callback} }($this);
            }

            my $min = ($timer->{_timer} < 0) ? 0 : $timer->{_timer};
            if ( $min < $min_time ) {
                $min_time = $min;
            }
        }
    }

    return ( $min_time );
}

## POD ##

=pod

=head1 NAME

Net::BGP::Peer - Class encapsulating BGP-4 peering session state and functionality

=head1 SYNOPSIS

    use Net::BGP::Peer;

    $peer = Net::BGP::Peer->new(
        Start                => 1,
        ThisID               => '10.0.0.1',
        ThisAS               => 64512,
        PeerID               => '10.0.0.2',
        PeerAS               => 64513,
        PeerPort             => 1179,
        ConnectRetryTime     => 300,
        HoldTime             => 60,
        KeepAliveTime        => 20,
        Listen               => 0,
        Passive              => 0,
        AnnounceRefresh      => 1,
        SupportCapabilities  => 1,
        SupportMBGP          => 1,
        SupportAS4           => 1,
	SupportADD_PATH          => 1,
        OpenCallback         => \&my_open_callback,
        KeepaliveCallback    => \&my_keepalive_callback,
        UpdateCallback       => \&my_update_callback,
        NotificationCallback => \&my_notification_callback,
        ErrorCallback        => \&my_error_callback
    );

    $peer = renew Net::BGP::Peer("$peer");

    $peer->start();
    $peer->stop();

    $peer->update($update);
    $peer->refresh($refresh);

    $version = $peer->version();

    $this_id = $peer->this_id();
    $this_as = $peer->this_as();
    $peer_id = $peer->peer_id();
    $peer_as = $peer->peer_as();

    $i_will  = $peer->support_capabilities();

    $i_mbgp  = $peer->support_mbgp();

    $i_can   = $peer->this_can_refresh();
    $peer_can= $peer->peer_can_refresh();

    $peer_as4= $peer->peer_can_as4();

    $listen  = $peer->is_listener();
    $passive = $peer->is_passive();
    $estab   = $peer->is_established();

    $trans   = $peer->transport($trans);
    @trans   = $peer->transports;

    $string  = $peer->asstring();

    $peer->set_open_callback(\&my_open_callback);
    $peer->set_established_callback(\&my_established_callback);
    $peer->set_keepalive_callback(\&my_keepalive_callback);
    $peer->set_update_callback(\&my_update_callback);
    $peer->set_notification_callback(\&my_notification_callback);
    $peer->set_error_callback(\&my_error_callback);

    $peer->add_timer(\&my_minute_timer, 60);
    $peer->remove_timer(\&my_minute_timer);

=head1 DESCRIPTION

This module encapsulates the state and functionality associated with a BGP
peering session. Each instance of a B<Net::BGP::Peer> object corresponds
to a peering session with a distinct peer and presents a programming
interface to manipulate the peering session state and exchange of routing
information. Through the methods provided by the B<Net::BGP::Peer> module,
a program can start or stop peering sessions, send BGP routing UPDATE
messages, and register callback functions which are invoked whenever the
peer receives BGP messages from its peer.

=head1 CONSTRUCTOR

I<new()> - create a new Net::BGP::Peer object

This is the constructor for Net::BGP::Peer objects. It returns a
reference to the newly created object. The following named parameters may
be passed to the constructor. Once the object is created, only the
callback function references can later be changed.

=head2 Start

Setting this parameter to a true value causes the peer to initiate a
session with its peer immediately after it is registered with the
B<Net::BGP::Process> object's I<add_peer()> method. If omitted or
set to a false value, the peer will remain in the Idle state until
the I<start()> method is called explicitly by the program. When in
the Idle state the peer will refuse connections and will not initiate
connection attempts.

=head2 ThisID

This parameter sets the BGP ID (IP address) of the B<Net::BGP::Peer>
object. It takes a string in IP dotted decimal notation.

=head2 ThisAS

This parameter sets the BGP Autonomous System number of the B<Net::BGP::Peer>
object. It takes an integer value in the range of a 16-bit unsigned integer.

=head2 PeerID

This parameter sets the BGP ID (IP address) of the object's peer. It takes
a string in IP dotted decimal notation.

=head2 PeerAS

This parameter sets the BGP Autonomous System number of the object's peer.
It takes an integer value in the range of a 16-bit unsigned integer.

=head2 PeerPort

This parameter sets the TCP port number on the peer to which to connect. It
must be in the range of a valid TCP port number.

=head2 ConnectRetryTime

This parameter sets the BGP ConnectRetry timer duration, the value of which
is given in seconds.

=head2 HoldTime

This parameter sets the BGP Hold Time duration, the value of which
is given in seconds.

=head2 KeepAliveTime

This parameter sets the BGP KeepAlive timer duration, the value of which
is given in seconds.

=head2 Listen

This parameter specifies whether the B<Net::BGP::Peer> will listen for
and accept connections from its peer. If set to a false value, the peer
will only initiate connections and will not accept connection attempts
from the peer (unless the B<Passive> parameter is set to a true value).
Note that this behavior is not specified by RFC 1771 and should be
considered non-standard. However, it is useful under certain circumstances
and should not present problems as long as one side of the connection is
configured to listen.

=head2 Passive

This parameter specifies whether the B<Net::BGP::Peer> will attempt to
initiate connections to its peer. If set to a true value, the peer will
only listen for connections and will not initate connections to its peer
(unless the B<Listen> parameter is set to false value). Note that this
behavior is not specified by RFC 1771 and should be considered non-standard.
However, it is useful under certain circumstances and should not present
problems as long as one side of the connection is configured to initiate
connections.

=head2 Refresh

This parameter specifies whether the B<Net::BGP::Peer> will annonce support
for route refresh ('soft re-configure' as specified by RFC 2918). No support
for route refresh is implemented - only the B<RefreshCallback> function.  This
has no effect if SupportCapabilities is FALSE.

=head2 SupportCapabilities

This parameter specifies whether the B<Net::BGP::Peer> will attempt to
negotiate capabilities.  You can set this to FALSE if talking to an old BGP
speaker that doesn't support it (you'll get a notification message for an
unsupported capability if this is the case).  This defaults to TRUE.

=head2 SupportMBGP

This parameter specifies whether the B<NET::BGP::Peer> will attempt to
negotiate MBGP.  Quagga (and probably others) need this if you want to send
the REFRESH capability. Today this just indicates support for IPv4 Unicast.
This defaults to TRUE.  This has no effect if SupportCapabilities is FALSE.

=head2 SupportAS4

This paramemter specifies whether outgoing connections from B<NET::BGP::Peer>
will attempt to negotiate AS4 (32 bit ASNs). For received connections, this
parameter has no effect - it only determines whether or not AS4 is negotiated
during outgoing connection.  For received connections, this will be changed
to TRUE (on the listening connection) whenever the appropriate OPEN capability
is received.  Note that the B<SupportCapabilities> must be true for this to
be sent.  This defaults to FALSE.

=head2 OpenCallback

This parameter sets the callback function which is invoked when the
peer receives an OPEN message. It takes a subroutine reference. See
L<"CALLBACK FUNCTIONS"> later in this manual for further details of
the conventions of callback invocation.

=head2 KeepaliveCallback

This parameter sets the callback function which is invoked when the
peer receives a KEEPALIVE message. It takes a subroutine reference.
See L<"CALLBACK FUNCTIONS"> later in this manual for further details
of the conventions of callback invocation.

=head2 UpdateCallback

This parameter sets the callback function which is invoked when the
peer receives an UPDATE message. It takes a subroutine reference. See
L<"CALLBACK FUNCTIONS"> later in this manual for further details of
the conventions of callback invocation.

=head2 RefreshCallback

This parameter sets the callback function which is invoked when the
peer receives a REFRESH message. It takes a subroutine reference. See
L<"CALLBACK FUNCTIONS"> later in this manual for further details of
the conventions of callback invocation.

=head2 NotificationCallback

This parameter sets the callback function which is invoked when the
peer receives a NOTIFICATION message. It takes a subroutine reference.
See L<"CALLBACK FUNCTIONS"> later in this manual for further details
of the conventions of callback invocation.

=head2 ErrorCallback

This parameter sets the callback function which is invoked when the
peer encounters an error and must send a NOTIFICATION message to its
peer. It takes a subroutine reference. See L<"CALLBACK FUNCTIONS">
later in this manual for further details of the conventions of callback
invocation.

I<renew> - fetch the existing Net::BGP::Peer object from the "object string".

This "reconstructor" returns a previeus constructed object from the
perl genereted string-context scalar of the object, eg.
I<Net::BGP::Peer=HASH(0x820952c)>.

=head1 ACCESSOR METHODS

I<start()> - start the BGP peering session with the peer

    $peer->start();

This method initiates the BGP peering session with the peer by
internally emitting the BGP Start event, which causes the peer
to initiate a transport-layer connection to its peer (unless
the B<Passive> parameter was set to a true value in the
constructor) and listen for a connection from the peer (unless
the B<Listen> parameter is set to a false value).

I<stop()> - cease the BGP peering session with the peer

    $peer->stop();

This method immediately ceases the peering session with the
peer by sending it a NOTIFICATION message with Error Code
Cease, closing the transport-layer connection, and entering
the Idle state.

I<update()> - send a BGP UPDATE message to the peer

    $peer->update($update);

This method sends the peer an UPDATE message. It takes a reference
to a Net::BGP::Update object. See the Net::BGP::Update
manual page for details on setting UPDATE attributes.

I<refresh()> - send a BGP REFRESH message to the peer

    $peer->refresh($refresh);

This method sends the peer a REFRESH message. It takes a reference
to a Net::BGP::Refesh object. If no argument is provided, a default
Net::BGP::Refresh object is constructed. See the Net::BGP::Refresh
manual page for details on setting REFRESH attributes.

I<transport()>

Returns the active transport object to the peer - See Net::BGP::Transport.

I<transports()>

Return a list of transport objects. The list will contain one or two elements.
The first will always be the primary transport object. If there are two
sessions (e.g. collision detection hasn't removed one of them), the sibling
will be returned as the second element of the list.

I<this_id()>

I<this_as()>

I<peer_id()>

I<peer_as()>

I<this_can_refresh()>

I<support_capabilities()>

I<support_mbgp()>

I<is_listener()>

I<is_passive()>

I<version()>

These are accessor methods for the corresponding constructor named parameters.
They retrieve the values set when the object was created, but the values cannot
be changed after object construction. Hence, they take no arguments.

I<is_established()>

This accessor method returns true if the peer has a established transport
connection - e.g. the peering is up.

I<peer_can_refresh()>

This accessor method returns a true value if connected to a peer that supports
refresh messages - otherwise a false value.

I<asstring()>

This accessor method returns a print friendly string with the local and remote
IP and AS numbers.

I<set_open_callback()>

I<set_established_callback()>

I<set_keepalive_callback()>

I<set_update_callback()>

I<set_refresh_callback()>

I<set_reset_callback()>

I<set_notification_callback()>

I<set_error_callback()>

These methods set the callback functions which are invoked whenever the
peer receives the corresponding BGP message type from its peer, or, in the
case of I<set_established_callback>, transitions to the relevant state. They
can be set in the constructor as well as with these methods. These methods
each take one argument, which is the subroutine reference to be invoked.
A callback function can be removed by calling the corresponding one of these
methods and passing it the perl I<undef> value. For callback definition and
invocation conventions see L<"CALLBACK FUNCTIONS"> later in this manual.

I<add_timer()> - add a program defined timer callback function

    $peer->add_timer(\&my_minute_timer, 60);

This method sets a program defined timer which invokes the specified callback
function when the timer expires. It takes two arguments: the first is a code
reference to the subroutine to be invoked when the timer expires, and the
second is the timer interval, in seconds. The program may set as many timers
as needed, and multiple timer callbacks may share the same interval. Program
timers add an asynchronous means for user code to gain control of the program
control flow - without them user code would only be invoked whenever BGP
events exposed by the module occur. They may be used to perform any necessary
action - for example, sending UPDATEs, starting or stopping the peering
session, house-keeping, etc.

I<remove_timer()> - remove a program defined timer callback function

    $peer->remove_timer(\&my_minute_timer);

This method removes a program defined timer callback which has been previously
set with the I<add_timer()> method. It takes a single argument: a reference
to the subroutine previously added.

=head1 CALLBACK FUNCTIONS

Whenever a B<Net::BGP::Peer> object receives one of the BGP protocol messages -
OPEN, KEEPALIVE, UPDATE, REFRESH, or NOTIFICATION - from its peer, or whenever it
encounters an error condition and must send a NOTIFICATION message to its peer,
the peer object will invoke a program defined callback function corresponding
to the event type, if one has been provided, to inform the application about
the event. These callback functions are installed as described in the preceding
section of the manual. Whenever any callback function is invoked, it is passed
one or more arguments, depending on the BGP message type associated with the
callback. The first argument passed to all of the callbacks is a reference
to the B<Net::BGP::Peer> object which the application may use to identify
which peer has signalled the event and to take appropriate action. For OPEN
and KEEPALIVE callbacks, this is the only argument passed. It is very unlikely
that applications will be interested in OPEN and KEEPALIVE events, since the
B<Net::BGP> module handles all details of OPEN and KEEPALIVE message processing
in order to establish and maintain BGP sessions. Callback handling for these
messages is mainly included for the sake of completeness. For UPDATE and
NOTIFICATION messages, however, most applications will install callback handlers.
Whenever an UPDATE, REFRESH, NOTIFICATION, or error handler is called, the object
will pass a second argument. In the first two cases, this is a B<Net::BGP::Update>
or B<Net::BGP::Refresh> object respectivly encapsulating the information contained
in the UPDATE or REFRESH message, while in the latter two cases it is a
B<Net::BGP::Notification> object encapsulating the information in the
NOTIFICATION message sent or received.

The RESET and ESTABLISHED callbacks are special, since they are used whenever an
established BGP session is reset, even though no message has been recieved or sent.
The REFRESH callback is also special, since it is also called without a REFRESH
object whenever a BGP session is established. The two callbacks can be used to
clear and retransmit a RIB from/to the peer in question.

Whenever a callback function is to be invoked, the action occuring internally is
the invocation of one of the following methods, corresponding to the event which
has occured:

I<open_callback()>

I<established_callback()>

I<keepalive_callback()>

I<update_callback()>

I<refresh_callback()>

I<reset_callback()>

I<notification_callback()>

I<error_callback()>

Internally, each of these methods just checks to see whether a program defined
callback function has been set and calls it if so, passing it arguments as
described above. As an alternative to providing subroutine references to the
constructor or through the I<set_open_callback()>, I<set_established_callback()>,
I<set_keepalive_callback()>, I<set_update_callback()>, I<set_refresh_callback()>,
I<set_reset_callback()>, I<set_notification_callback()>, and I<set_error_callback()>
methods, an application may effect a similar result by sub-classing the
B<Net::BGP::Peer> module and overridding the defintions of the above methods
to perform whatever actions would have been executed by ordinary callback functions.
The overridden methods are passed the same arguments as the callback functions.
This method might offer an advantage in organizing code according to different
derived classes which apply specifc routing policies.

=head1 ERROR HANDLING

There are two possibilities for error handling callbacks to be invoked. The first
case occurs when the peer receives a NOTIFICATION messages from its peer. The
second case occurs when the peer detects an error condition while processing an
incoming BGP message or when some other protocol covenant is violated - for
example if a KEEPALIVE or UPDATE message is not received before the peer's
Keepalive timer expires. In this case, the peer responds by sending a NOTIFICATION
message to its peer. In the former case the I<notification_callback()> method
is invoked as described above to handle the error, while in the latter the
I<error_callback()> method is invoked to inform the application that it has
encountered an error. Both methods are passed a B<Net::BGP::Notification>
object encapsulating the details of the error. In both cases, the transport-layer
connection and BGP session are closed and the peer transitions to the Idle state.
The error handler callbacks can examine the cause of the error and take appropriate
action. This could be to attempt to re-establish the session (perhaps after
sleeping for some amount of time), or to unregister the peer object from the
B<Net::BGP::Process> object and permanently end the session (for the duration
of the application's running time), or to log the event to a file on the host
system, or some combination of these or none.

=head1 SEE ALSO

Net::BGP, Net::BGP::Process, Net::BGP::Update, Net::BGP::Transport,
Net::BGP::Refresh, Net::BGP::Notification

=head1 AUTHOR

Stephen J. Scheck <code@neurosphere.com>

=cut

## End Package Net::BGP::Peer ##

1;
