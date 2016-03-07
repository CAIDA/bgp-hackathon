#!/usr/bin/perl

package Net::BGP::Transport;
use bytes;
use Socket qw(PF_INET SOCK_STREAM pack_sockaddr_in inet_pton); #XXX
use strict;
use Errno qw(EAGAIN);
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

## BGP General Constant Definitions ##

sub BGP_MESSAGE_HEADER_LENGTH { 19 }
sub BGP_MAX_MESSAGE_LENGTH    { 4096 }
sub BGP_CONNECT_RETRY_TIME    { 120 }
sub BGP_HOLD_TIME             { 90 }
sub BGP_KEEPALIVE_TIME        { 30 }

## BGP Finite State Machine State Enumerations ##

sub BGP_STATE_IDLE         { 1 }
sub BGP_STATE_CONNECT      { 2 }
sub BGP_STATE_ACTIVE       { 3 }
sub BGP_STATE_OPEN_SENT    { 4 }
sub BGP_STATE_OPEN_CONFIRM { 5 }
sub BGP_STATE_ESTABLISHED  { 6 }

## BGP State Names ##

@BGP_STATES = qw( Null Idle Connect Active OpenSent OpenConfirm Established );

## BGP Event Enumerations ##

sub BGP_EVENT_START                        { 1 }
sub BGP_EVENT_STOP                         { 2 }
sub BGP_EVENT_TRANSPORT_CONN_OPEN          { 3 }
sub BGP_EVENT_TRANSPORT_CONN_CLOSED        { 4 }
sub BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED   { 5 }
sub BGP_EVENT_TRANSPORT_FATAL_ERROR        { 6 }
sub BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED  { 7 }
sub BGP_EVENT_HOLD_TIMER_EXPIRED           { 8 }
sub BGP_EVENT_KEEPALIVE_TIMER_EXPIRED      { 9 }
sub BGP_EVENT_RECEIVE_OPEN_MESSAGE         { 10 }
sub BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE   { 11 }
sub BGP_EVENT_RECEIVE_UPDATE_MESSAGE       { 12 }
sub BGP_EVENT_RECEIVE_NOTIFICATION_MESSAGE { 13 }
sub BGP_EVENT_RECEIVE_REFRESH_MESSAGE      { 14 }

## BGP Event Names ##

@BGP_EVENTS = (
    'Null',
    'BGP Start',
    'BGP Stop',
    'BGP Transport connection open',
    'BGP Transport connection closed',
    'BGP Transport connection open failed',
    'BGP Transport fatal error',
    'ConnectRetry timer expired',
    'Hold Timer expired',
    'KeepAlive timer expired',
    'Receive OPEN message',
    'Receive KEEPALIVE message',
    'Receive UPDATE message',
    'Receive NOTIFICATION message',
    'Receive REFRESH message'
);

## BGP Protocol Message Type Enumerations ##

sub BGP_MESSAGE_OPEN         { 1 }
sub BGP_MESSAGE_UPDATE       { 2 }
sub BGP_MESSAGE_NOTIFICATION { 3 }
sub BGP_MESSAGE_KEEPALIVE    { 4 }
sub BGP_MESSAGE_REFRESH      { 5 }

## BGP Open Optional Parameter Types ##

sub BGP_OPTION_AUTH          { 1 }
sub BGP_OPTION_CAPABILITIES  { 2 }

## BGP Open Capabilities Parameter Types
sub BGP_CAPABILITY_MBGP        {   1 }
sub BGP_CAPABILITY_REFRESH     {   2 }
sub BGP_CAPABILITY_AS4         {  65 }
sub BGP_CAPABILITY_ADD_PATH    {  69 }
sub BGP_CAPABILITY_REFRESH_OLD { 128 }

## Event-Message Type Correlation ##

@BGP_EVENT_MESSAGE_MAP = (
    undef,
    BGP_EVENT_RECEIVE_OPEN_MESSAGE,
    BGP_EVENT_RECEIVE_UPDATE_MESSAGE,
    BGP_EVENT_RECEIVE_NOTIFICATION_MESSAGE,
    BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE,
    BGP_EVENT_RECEIVE_REFRESH_MESSAGE
);

## BGP FSM State Transition Table ##

@BGP_FSM = (
    undef,                                     # Null (zero placeholder)

    [                                          # Idle
        \&_close_session,                      # Default transition
        \&_handle_bgp_start_event              # BGP_EVENT_START
    ],
    [                                          # Connect
        \&_close_session,                      # Default transition
        \&_ignore_start_event,                 # BGP_EVENT_START
        undef,                                 # BGP_EVENT_STOP
        \&_handle_bgp_conn_open,               # BGP_EVENT_TRANSPORT_CONN_OPEN
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_CLOSED
        \&_handle_connect_retry_restart,       # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        undef,                                 # BGP_EVENT_TRANSPORT_FATAL_ERROR
        \&_handle_bgp_start_event              # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
    ],
    [                                          # Active
        \&_close_session,                      # Default transition
        \&_ignore_start_event,                 # BGP_EVENT_START
        undef,                                 # BGP_EVENT_STOP
        \&_handle_bgp_conn_open,               # BGP_EVENT_TRANSPORT_CONN_OPEN
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_CLOSED
        \&_handle_connect_retry_restart,       # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        undef,                                 # BGP_EVENT_TRANSPORT_FATAL_ERROR
        \&_handle_bgp_start_event              # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
    ],
    [                                          # OpenSent
        \&_handle_bgp_fsm_error,               # Default transition
        \&_ignore_start_event,                 # BGP_EVENT_START
        \&_cease,                              # BGP_EVENT_STOP
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN
        \&_handle_open_sent_disconnect,        # BGP_EVENT_TRANSPORT_CONN_CLOSED
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        \&_close_session,                      # BGP_EVENT_TRANSPORT_FATAL_ERROR
        undef,                                 # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
        \&_handle_hold_timer_expired,          # BGP_EVENT_HOLD_TIMER_EXPIRED
        undef,                                 # BGP_EVENT_KEEPALIVE_TIMER_EXPIRED
        \&_handle_bgp_open_received            # BGP_EVENT_RECEIVE_OPEN_MESSAGE
    ],
    [                                          # OpenConfirm
        \&_handle_bgp_fsm_error,               # Default transition
        \&_ignore_start_event,                 # BGP_EVENT_START
        \&_cease,                              # BGP_EVENT_STOP
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN
        \&_close_session,                      # BGP_EVENT_TRANSPORT_CONN_CLOSED
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        \&_close_session,                      # BGP_EVENT_TRANSPORT_FATAL_ERROR
        undef,                                 # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
        \&_handle_hold_timer_expired,          # BGP_EVENT_HOLD_TIMER_EXPIRED
        \&_handle_keepalive_expired,           # BGP_EVENT_KEEPALIVE_TIMER_EXPIRED
        undef,                                 # BGP_EVENT_RECEIVE_OPEN_MESSAGE
        \&_handle_receive_keepalive_message,   # BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE
        undef,                                 # BGP_EVENT_RECEIVE_UPDATE_MESSAGE
        \&_handle_receive_notification_message,# BGP_EVENT_RECEIVE_NOTIFICATION_MESSAGE
        \&_handle_receive_refresh_message      # BGP_EVENT_RECEIVE_REFRESH_MESSAGE
    ],
    [                                          # Established
        \&_handle_bgp_fsm_error,               # Default transition
        \&_ignore_start_event,                 # BGP_EVENT_START
        \&_cease,                              # BGP_EVENT_STOP
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN
        \&_close_session,                      # BGP_EVENT_TRANSPORT_CONN_CLOSED
        undef,                                 # BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED
        \&_close_session,                      # BGP_EVENT_TRANSPORT_FATAL_ERROR
        undef,                                 # BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED
        \&_handle_hold_timer_expired,          # BGP_EVENT_HOLD_TIMER_EXPIRED
        \&_handle_keepalive_expired,           # BGP_EVENT_KEEPALIVE_TIMER_EXPIRED
        undef,                                 # BGP_EVENT_RECEIVE_OPEN_MESSAGE
        \&_handle_receive_keepalive_message,   # BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE
        \&_handle_receive_update_message,      # BGP_EVENT_RECEIVE_UPDATE_MESSAGE
        \&_handle_receive_notification_message,# BGP_EVENT_RECEIVE_NOTIFICATION_MESSAGE
        \&_handle_receive_refresh_message      # BGP_EVENT_RECEIVE_REFRESH_MESSAGE
    ]
);

## Socket States ##

sub AWAITING_HEADER_START     { 1 }
sub AWAITING_HEADER_FRAGMENT  { 2 }
sub AWAITING_MESSAGE_FRAGMENT { 3 }

## Export Tag Definitions ##

@EXPORT      = ();
@EXPORT_OK   = ();
%EXPORT_TAGS = (
    ALL      => [ @EXPORT, @EXPORT_OK ]
);

## Module Imports ##

use Scalar::Util qw( weaken );
use Errno qw(EINPROGRESS ENOTCONN);
use Exporter;
use IO::Socket::INET6; #XXX
use Carp;
use Carp qw(cluck);
use Net::BGP::Notification qw( :errors );
use Net::BGP::Refresh;
use Net::BGP::Update;

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
	_parent                => undef,
        _sibling               => undef,
        _bgp_version           => BGP_VERSION_4,
        _fsm_state             => BGP_STATE_IDLE,
	_peer_refresh          => FALSE,
        _peer_as4              => FALSE,
        _peer_mbgp             => FALSE,
        _peer_announced_id     => undef,
        _event_queue           => [],
        _message_queue         => [],
        _hold_time             => BGP_HOLD_TIME,
        _hold_timer            => undef,
        _keep_alive_time       => BGP_KEEPALIVE_TIME,
        _keep_alive_timer      => undef,
        _connect_retry_time    => BGP_CONNECT_RETRY_TIME,
        _connect_retry_timer   => undef,
        _peer_socket           => undef,
	_peer_socket_connected => FALSE, # is AWARE - Not established, not socket->connected!
        _last_timer_update     => undef,
        _in_msg_buffer         => '',
        _in_msg_buf_state      => AWAITING_HEADER_START,
        _in_msg_buf_bytes_exp  => 0,
        _in_msg_buf_type       => 0,
        _out_msg_buffer        => ''
    };

    bless($this, $class);

    while ( defined($arg = shift()) ) {
        $value = shift();

        if ( $arg =~ /start/i ) {
            $this->start();
        }
        elsif ( $arg =~ /parent/i ) {
            $this->{_parent} = $value;
        }
        elsif ( $arg =~ /holdtime/i ) {
            $this->{_hold_time} = $value;
        }
        elsif ( $arg =~ /connectretrytime/i ) {
            $this->{_connect_retry_time} = $value;
        }
        elsif ( $arg =~ /keepalivetime/i ) {
            $this->{_keep_alive_time} = $value;
        }
        else {
            croak "unrecognized argument $arg\n";
        }
    }

    return ( $this );
}

## Public Object Methods ##

sub start
{
    my $this = shift();
    $this->_enqueue_event(BGP_EVENT_START);
}

sub stop
{
    my $this = shift();
    $this->{_fsm_state} = $this->_cease();
}

sub version
{
    return shift->{_bgp_version};
}

sub is_established
{
    return ( (shift->{_fsm_state} == BGP_STATE_ESTABLISHED) ? 1 : 0 );
}

sub can_refresh
{
    return shift->{_peer_refresh};
}

sub can_as4
{
    return shift->{_peer_as4};
}

sub can_mbgp
{
    return shift->{_peer_mbgp};
}

sub update
{
    my ($this, $update) = @_;

    my $result = FALSE;
    if ( $this->{_fsm_state} == BGP_STATE_ESTABLISHED ) {

        my $encoded = $update->_encode_message( { as4 => $this->{_peer_as4} } );

        my $buffer = $this->_encode_bgp_update_message($encoded);
        $this->_send_msg($buffer);
        $result = TRUE;
    }

    return $result;
}

sub refresh
{
    my $this = shift;

    my ($refresh) = @_;
    $refresh = Net::BGP::Refresh->new(@_) unless ref $refresh eq 'Net::BGP::Refresh';

    my $result = FALSE;
    if (( $this->{_fsm_state} == BGP_STATE_ESTABLISHED ) && $this->{_peer_refresh}) {
        my $buffer = $this->_encode_bgp_refresh_message($refresh->_encode_message());
        $this->_send_msg($buffer);
        $result = TRUE;
    }

    return $result;
}

sub parent
{
    return shift->{_parent};
}

sub sibling
{
    my $this = shift();
    return undef unless defined $this->{_sibling};
    return undef unless $this->parent->transport eq $this;
    return $this->{_sibling};
}

## Private Class Methods ##

sub _clone
{
    my $this = shift();

    croak 'Cannot have more than one clone at a time!' if defined $this->{_sibling};

    my $clone = {};
    foreach my $key ( keys(%{ $this }) ) {
        $clone->{$key} = $this->{$key};
    }

    bless($clone, ref($this));

    # override some of the inherited properties
    $clone->{_peer_refresh}         = FALSE;
    $clone->{_peer_announced_id}    = undef;
    $clone->{_hold_timer}           = undef;
    $clone->{_keep_alive_timer}     = undef;
    $clone->{_fsm_state}            = BGP_STATE_CONNECT;
    $clone->{_event_queue}          = [];
    $clone->{_message_queue}        = [];
    $clone->{_peer_socket}          = undef;
    $clone->{_peer_socket_connected}= FALSE;
    $clone->{_connect_retry_timer}  = undef;
    $clone->{_last_timer_update}    = undef;
    $clone->{_in_msg_buffer}        = '';
    $clone->{_in_msg_buf_state}     = AWAITING_HEADER_START;
    $clone->{_in_msg_buf_bytes_exp} = 0;
    $clone->{_in_msg_buf_type}      = 0;
    $clone->{_out_msg_buffer}       = '';
    $clone->{_sibling}              = $this;
    $this->{_sibling}               = $clone;

    if ( $this->{_fsm_state} != BGP_STATE_IDLE ) {
        $clone->start();
    }

    return $clone;
}

## Private Object Methods ##

## This creates AND throws a ::Notification object.
sub _error
{
    my $this = shift();

    Net::BGP::Notification->throw(
        ErrorCode    => shift(),
        ErrorSubCode => shift() || BGP_ERROR_SUBCODE_NULL,
        ErrorData    => shift()
    );
}

sub _is_connected
{
    my $this = shift();
    return ( $this->{_peer_socket_connected} );
}

sub _get_socket
{
    my $this = shift();
    return ( $this->{_peer_socket} );
}

sub _set_socket
{
    my ($this, $socket) = @_;
    $this->{_peer_socket} = $socket;
    $this->{_peer_socket_connected} = TRUE;
}

sub _enqueue_event
{
    my $this = shift();
    push(@{ $this->{_event_queue} }, shift());
}

sub _dequeue_event
{
    my $this = shift();
    return ( shift(@{ $this->{_event_queue} }) );
}

sub _enqueue_message
{
    my $this = shift();
    push(@{ $this->{_message_queue} }, shift());
}

sub _dequeue_message
{
    my $this = shift();
    return ( shift(@{ $this->{_message_queue} }) );
}

sub _handle_event
{
    my ($this, $event) = @_;

    my $state = my $next_state = $this->{_fsm_state};

    my $action =
           $BGP_FSM[$state]->[$event]
        || $BGP_FSM[$state]->[0] ## default action
        || undef ;

    eval {
        $next_state = $action->($this) if defined $action;
    };
    if (my $oops = $@)
    {
        if (UNIVERSAL::isa($oops, 'Net::BGP::Notification'))
        {
            $this->_kill_session($oops);
            $next_state = BGP_STATE_IDLE;
        }
        else
        {
            die $oops;
        }
    }

    # transition to next state
    $this->{_fsm_state} = $next_state if defined $next_state;

    ## trigger callbacks if we changed states
    if ($next_state != $state)
    {
        if ( $state == BGP_STATE_ESTABLISHED )
        {
            ## session has terminated
            ##
            $this->parent->reset_callback(undef)
        }
        elsif ( $next_state == BGP_STATE_ESTABLISHED )
        {
            ## newly established session
            ##
            $this->parent->refresh_callback(undef);
        }

        # trigger post-transition actions
        $this->_trigger_post_transition_action($state, $next_state);
    }
}

sub _trigger_post_transition_action
{
    my ($this, $pre_state, $pos_state) = @_;

    # TODO:
    #
    # This needs to be broken out into a separate table similar to $BGP_FSM
    # which triggers actions prior to state transition. Or, alternately,
    # $BGP_FSM could be augmented to have an array of subrefs, one each for the
    # pre- and post- transition action, rather than the current scalar subref.
    # But I'm too lazy to refactor the entire table right now, so just handle
    # the single current use case of firing the ESTABLISHED callback...

    if (($pre_state == BGP_STATE_OPEN_CONFIRM) && ($pos_state == BGP_STATE_ESTABLISHED)) {
        $this->parent->established_callback();
    }
}

sub _handle_pending_events
{
    my $this = shift();
    my $event;

    # flush the outbound message buffer
    if ( length($this->{_out_msg_buffer}) ) {
        $this->_send_msg();
    }

    while ( defined($event = $this->_dequeue_event()) ) {      
	$this->_handle_event($event);
    }
}

sub _update_timers
{
    my ($this, $delta) = @_;
    my ($timer, $key, $min, $min_time);
    my %timers = (
        _connect_retry_timer => BGP_EVENT_CONNECT_RETRY_TIMER_EXPIRED,
        _hold_timer          => BGP_EVENT_HOLD_TIMER_EXPIRED,
        _keep_alive_timer    => BGP_EVENT_KEEPALIVE_TIMER_EXPIRED
    );

    $min_time = 3600;
    if ( length($this->{_out_msg_buffer}) ) {
        $min_time = 0;
    }

    # Update BGP timers
    foreach $timer ( keys(%timers) ) {
        if ( defined($this->{$timer}) ) {
            $this->{$timer} -= $delta;

            if ( $this->{$timer} <= 0 ) {
                $this->{$timer} = 0;
                $this->_enqueue_event($timers{$timer});
            }

            if ( $this->{$timer} < $min_time ) {
                $min_time = $this->{$timer};
            }
        }
    }

    # Got a sibling-child?
    if (defined $this->sibling)
     {
      my $sibmin = $this->sibling->_update_timers($delta);
      $min_time = $sibmin if $sibmin < $min_time;
     }

    return $min_time;
}

sub _send_msg
{
    my ($this, $msg, $oktofail) = @_;


    unless (defined $this->{_peer_socket}) {
        return if $oktofail;
        cluck $this->parent->asstring . ": Internal error - no _peer_socket - Connection is shutdown\n";
        $this->_cease;
        return;
    }

    my $buffer = $this->{_out_msg_buffer} . $msg;
    my $sent = $this->{_peer_socket}->syswrite($buffer);

    if ( ! defined($sent) ) {
        return if $oktofail; # In a _cease process - Don't complain...
	if ($!{EAGAIN} == 0) {
	    warn $this->parent->asstring . ": Error on socket write: $! - Connection is shutdown\n";
            $this->_cease;
	}
        return;
    }

    $this->{_out_msg_buffer} = substr($buffer, $sent);
}

sub _handle_socket_read_ready
{
    my $this = shift();

    my $socket = $this->{_peer_socket};

    unless (defined $socket) {
      warn $this->parent->asstring . ": Connection lost - Connection is formaly shutdown now\n";
      $this->_cease;
      return;
    }

    my $conn_closed = FALSE;
    my $buffer = $this->{_in_msg_buffer};

    if ( $this->{_in_msg_buf_state} == AWAITING_HEADER_START ) {
        my $num_read = $socket->sysread($buffer, BGP_MESSAGE_HEADER_LENGTH, length($buffer));

        if ($!) { # Something went wrong with none-blocking connect()
          $this->{_peer_socket} = $socket = undef;
          $this->_enqueue_event(BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED);
          return;
        }

        if ( $num_read == 0 ) {
            $conn_closed = TRUE;
        }
        elsif ( $num_read != BGP_MESSAGE_HEADER_LENGTH ) {
            $this->{_in_msg_buf_state} = AWAITING_HEADER_FRAGMENT;
            $this->{_in_msg_buf_bytes_exp} = (BGP_MESSAGE_HEADER_LENGTH) - ($num_read);
            $this->{_in_msg_buffer} = $buffer;
        }
        else {
            $this->_decode_bgp_message_header($buffer);
            $this->{_in_msg_buffer} = '';
        }
    }
    elsif ( $this->{_in_msg_buf_state} == AWAITING_HEADER_FRAGMENT ) {
        my $num_read = $socket->sysread($buffer, $this->{_in_msg_buf_bytes_exp}, length($buffer));
        if ( $num_read == 0 ) {
            $conn_closed = TRUE;
        }
        elsif ( $num_read == $this->{_in_msg_buf_bytes_exp} ) {
            $this->_decode_bgp_message_header($buffer);
            $this->{_in_msg_buffer} = '';
        }
        else {
            $this->{_in_msg_buf_bytes_exp} -= $num_read;
            $this->{_in_msg_buffer} = $buffer;
        }
    }
    elsif ( $this->{_in_msg_buf_state} == AWAITING_MESSAGE_FRAGMENT ) {
        my $num_read = $socket->sysread($buffer, $this->{_in_msg_buf_bytes_exp}, length($buffer));
        if ( ($num_read == 0) && ($this->{_in_msg_buf_bytes_exp} != 0) ) {
            $conn_closed = TRUE;
        }
        elsif ( $num_read == $this->{_in_msg_buf_bytes_exp} ) {
            $this->_enqueue_message($buffer);
            $this->_enqueue_event($BGP_EVENT_MESSAGE_MAP[$this->{_in_msg_buf_type}]);
            $this->{_in_msg_buffer} = '';
            $this->{_in_msg_buf_state} = AWAITING_HEADER_START;
        }
        else {
            $this->{_in_msg_buf_bytes_exp} -= $num_read;
            $this->{_in_msg_buffer} = $buffer;
        }
    }
    else {
        croak("unknown socket state!\n");
    }

    if ( $conn_closed ) {
     $this->_enqueue_event(BGP_EVENT_TRANSPORT_CONN_CLOSED);
    }
}

sub _handle_socket_write_ready
{
 my $this = shift();
 return unless defined($this->{_peer_socket}); # Might have been closed by _handle_socket_read_ready!
 $this->{_peer_socket_connected} = TRUE;
 $this->_enqueue_event(BGP_EVENT_TRANSPORT_CONN_OPEN);
}

sub _handle_socket_error_condition
{
    my $this = shift();
    warn "_handle_socket_error_condition()\n" . $this->{_peer_socket}->error(), "\n";
}

sub _close_session
{
    my $this = shift();
    my $socket = $this->{_peer_socket};

    if ( defined($socket) ) {
        $socket->close();
    }

    $this->{_peer_socket} = $socket = undef;
    $this->{_peer_socket_connected} = FALSE;
    $this->{_in_msg_buffer} = '';
    $this->{_out_msg_buffer} = '';
    $this->{_in_msg_buf_state} = AWAITING_HEADER_START;
    $this->{_hold_timer} = undef;
    $this->{_keep_alive_timer} = undef;
    $this->{_connect_retry_timer} = undef;
    $this->{_message_queue} = [];

    return ( BGP_STATE_IDLE );
}

sub _kill_session
{
    my ($this, $error) = @_;
    my $buffer;

    if (defined($this->{_peer_socket})) {
      $buffer = $this->_encode_bgp_notification_message(
        $error->error_code(),
        $error->error_subcode(),
        $error->error_data()
      );

      $this->_send_msg($buffer,1);
      $this->_close_session();
    };

    # invoke user callback function
    $this->parent->error_callback($error);
}

sub _ignore_start_event
{
    my $this = shift();
    return ( $this->{_fsm_state} );
}

sub _handle_receive_keepalive_message
{
    my $this = shift();

    # restart Hold Timer
    if ( $this->{_hold_time} != 0 ) {
        $this->{_hold_timer} = $this->{_hold_time};
    }

    # invoke user callback function
    $this->parent->keepalive_callback();

    return ( BGP_STATE_ESTABLISHED );
}

sub _handle_receive_update_message
{
    my $this = shift();
    my ($buffer, $update);

    # restart Hold Timer
    if ( $this->{_hold_time} != 0 ) {
        $this->{_hold_timer} = $this->{_hold_time};
    }

    $buffer = $this->_dequeue_message();
    $update = Net::BGP::Update->_new_from_msg(
        $buffer,
        { as4 => $this->{_peer_as4} }
    );

    # invoke user callback function
    $this->parent->update_callback($update);

    return ( BGP_STATE_ESTABLISHED );
}

sub _handle_receive_refresh_message
{
    my $this = shift();
    my ($buffer, $refresh);

    # restart Hold Timer
    if ( $this->{_hold_time} != 0 ) {
        $this->{_hold_timer} = $this->{_hold_time};
    }

    $buffer = $this->_dequeue_message();
    $refresh = Net::BGP::Refresh->_new_from_msg($buffer);

    unless ( $this->parent->this_can_refresh ) {
        Net::BGP::Notification->throw(
            ErrorCode => BGP_ERROR_CODE_FINITE_STATE_MACHINE
        );
    }

    # invoke user callback function
    $this->parent->refresh_callback($refresh);

    return ( BGP_STATE_ESTABLISHED );
}

sub _handle_receive_notification_message
{
    my $this = shift();
    my $error;

    $error = $this->_decode_bgp_notification_message($this->_dequeue_message());
    $this->_close_session();

    # invoke user callback function
    $this->parent->notification_callback($error);

    return ( BGP_STATE_IDLE );
}

sub _handle_keepalive_expired
{
    my $this = shift();
    my $buffer;

    # send KEEPALIVE message to peer
    $buffer = $this->_encode_bgp_keepalive_message();
    $this->_send_msg($buffer);

    # restart KeepAlive timer
    $this->{_keep_alive_timer} = $this->{_keep_alive_time};

    return ( $this->{_fsm_state} );
}

sub _handle_hold_timer_expired
{
    my $this = shift();

    $this->_error(BGP_ERROR_CODE_HOLD_TIMER_EXPIRED);
}

sub _handle_bgp_fsm_error
{
    my $this = shift();

    $this->_error(BGP_ERROR_CODE_FINITE_STATE_MACHINE);
}

sub _handle_bgp_conn_open
{
    my $this = shift();
    my $buffer;

    # clear ConnectRetry timer
    $this->{_connect_retry_timer} = undef;

    # send OPEN message to peer
    $buffer = $this->_encode_bgp_open_message();
    $this->_send_msg($buffer);

    return ( BGP_STATE_OPEN_SENT );
}

sub _handle_collision_selfdestuct
{
    my $this = shift;
    $this->stop();
    $this->parent->transport($this->{_sibling});
    $this->{_sibling}->{_sibling} = undef;
}

sub _handle_bgp_open_received
{
    my $this = shift();
    my ($buffer, $this_id, $peer_id);

    if ( ! $this->_decode_bgp_open_message($this->_dequeue_message()) ) {
        ; # do failure stuff
        return ( BGP_STATE_IDLE );
    }

    # check for connection collision
    if ( defined($this->{_sibling}) ) {
        if ( ($this->{_sibling}->{_fsm_state} == BGP_STATE_OPEN_SENT) ||
             ($this->{_sibling}->{_fsm_state} == BGP_STATE_OPEN_CONFIRM) ) {

            $this_id = unpack('N', inet_aton($this->parent->this_id));
            $peer_id = unpack('N', inet_aton($this->parent->peer_id));

            if ( $this_id < $peer_id ) {
		$this->_handle_collision_selfdestuct;
                return ( BGP_STATE_IDLE );
            }
            else {
                $this->{_sibling}->_handle_collision_selfdestuct;
            }
        }
        elsif ( ($this->{_sibling}->{_fsm_state} == BGP_STATE_ESTABLISHED) ) {
            $this->_handle_collision_selfdestuct;
            return ( BGP_STATE_IDLE );
        }
	else { # Other in Idle, conect, active
          $this->{_sibling}->_handle_collision_selfdestuct;
	}
    }

    # clear the message buffer after decoding and validation
    $this->{_message} = undef;

    # send KEEPALIVE message to peer
    $buffer = $this->_encode_bgp_keepalive_message();
    $this->_send_msg($buffer);

    # set Hold Time and KeepAlive timers
    if ( $this->{_hold_time} != 0 ) {
        $this->{_hold_timer} = $this->{_hold_time};
        $this->{_keep_alive_timer} = $this->{_keep_alive_time};
    }

    # invoke user callback function
    $this->parent->open_callback();

    # transition to state OpenConfirm
    return ( BGP_STATE_OPEN_CONFIRM );
}

sub _handle_open_sent_disconnect
{
    my $this = shift();

    $this->_close_session();
    return ( $this->_handle_connect_retry_restart() );
}

sub _handle_connect_retry_restart
{
    my $this = shift();

    # restart ConnectRetry timer
    $this->{_connect_retry_timer} = $this->{_connect_retry_time};

    return ( BGP_STATE_ACTIVE );
}

sub _handle_bgp_start_event
{
    my $this = shift();
    my ($socket, $proto, $remote_addr, $this_addr, $rv);

    # initialize ConnectRetry timer
    if ( ! $this->parent->is_passive ) {
        $this->{_connect_retry_timer} = $this->{_connect_retry_time};
    }

    # initiate the TCP transport connection
    if ( ! $this->parent->is_passive ) {

	my $family;
	my $pf_family;
	if ($this->parent->peer_id =~ /\:/) {
		$family = AF_INET6;
		$pf_family = PF_INET6;
	} else {
		$family = AF_INET;
		$pf_family = PF_INET;
	}

        eval {
            $socket = IO::Socket::INET6->new( Domain => $family ); #XXX
            if ( ! defined($socket) ) {
                die("IO::Socket construction failed");
            }

            $proto = getprotobyname('tcp');
            $rv = $socket->socket($pf_family, SOCK_STREAM, $proto); #XXX
            if ( ! defined($rv) ) {
                die("socket() failed");
            }

	    if ($family eq AF_INET6) {
            	$this_addr = sockaddr_in6(0, inet_pton($family, $this->parent->this_id)); #XXX
            } else {
            	$this_addr = sockaddr_in(0, inet_pton($family, $this->parent->this_id)); #XXX
            }
            $rv = $socket->bind($this_addr);
            if ( ! $rv ) {
                die("bind() failed");
            }

            $rv = $socket->blocking(FALSE);
            if ( ! defined($rv) ) {
                die("set socket non-blocking failed");
            }

	    if ($family eq AF_INET6) {
            	$remote_addr = sockaddr_in6($this->parent->peer_port, inet_pton($family, $this->parent->peer_id)); #XXX
            } else {
            	$remote_addr = sockaddr_in($this->parent->peer_port, inet_pton($family, $this->parent->peer_id)); #XXX
            }
            $rv = $socket->connect($remote_addr);
            if ( ! defined($rv) ) {
                die "OK - but connect() failed: $!" unless ($! == EINPROGRESS);
            }

            # $rv = $socket->blocking(TRUE);
            # if ( ! defined($rv) ) {
            #     die("set socket blocking failed");
            # }
        };

        # check for exception in transport initiation
        if ( $@ ) {
	    carp $@ unless $@ =~ /^OK/;
            if ( defined($socket) ) {
                $socket->close();
            }
            $this->{_peer_socket} = $socket = undef;
            $this->_enqueue_event(BGP_EVENT_TRANSPORT_CONN_OPEN_FAILED);
        }

        $this->{_peer_socket} = $socket;
        $this->{_peer_socket_connected} = FALSE;
    }

    return ( BGP_STATE_CONNECT );
}

sub _min
{
    my ($a, $b) = @_;
    return ( ($a < $b) ? $a : $b );
}

sub _cease
{
    my $this = shift();

    if ( $this->{_fsm_state} == BGP_STATE_ESTABLISHED ) {
	$this->parent->reset_callback();
    }

    my $error = Net::BGP::Notification->new( ErrorCode => BGP_ERROR_CODE_CEASE );

    $this->_kill_session($error);

    return ( BGP_STATE_IDLE );
}

sub _encode_bgp_message
{
    my ($this, $type, $payload) = @_;
    my ($buffer, $length);

    $buffer = '';
    $length = BGP_MESSAGE_HEADER_LENGTH;

    if ( defined($payload) ) {
       $length += length($payload);
       $buffer = $payload;
    }

    # encode the type field
    $buffer = pack('C', $type) . $buffer;

    # encode the length field
    $buffer = pack('n', $length) . $buffer;

    # encode the marker field
    if ( defined($this->{_auth_data}) ) {
        $buffer = $this->{_auth_data} . $buffer;
    }
    else {
        $buffer = (pack('C', 0xFF) x 16) . $buffer;
    }

    return ( $buffer );
}

sub _decode_bgp_message_header
{
    my ($this, $header) = @_;
    my ($marker, $length, $type);

    # validate the BGP message header length
    if ( length($header) != BGP_MESSAGE_HEADER_LENGTH ) {
        $this->_error(
            BGP_ERROR_CODE_MESSAGE_HEADER,
            BGP_ERROR_SUBCODE_BAD_MSG_LENGTH,
            pack('n', length($header))
        );
    }

    # decode and validate the message header Marker field
    $marker = substr($header, 0, 16);
    if ( $marker ne (pack('C', 0xFF) x 16) ) {
        $this->_error(BGP_ERROR_CODE_MESSAGE_HEADER,
                      BGP_ERROR_SUBCODE_CONN_NOT_SYNC);
    }

    # decode and validate the message header Length field
    $length = unpack('n', substr($header, 16, 2));
    if ( ($length < BGP_MESSAGE_HEADER_LENGTH) || ($length > BGP_MAX_MESSAGE_LENGTH) ) {
        $this->_error(
            BGP_ERROR_CODE_MESSAGE_HEADER,
            BGP_ERROR_SUBCODE_BAD_MSG_LENGTH,
            pack('n', $length)
        );
    }

    # decode and validate the message header Type field
    $type = unpack('C', substr($header, 18, 1));
    if ( ($type < BGP_MESSAGE_OPEN) || ($type > BGP_MESSAGE_REFRESH) ) {
        $this->_error(
            BGP_ERROR_CODE_MESSAGE_HEADER,
            BGP_ERROR_SUBCODE_BAD_MSG_TYPE,
            pack('C', $type)
        );
    }

    if ( $type == BGP_MESSAGE_KEEPALIVE ) {
        $this->{_in_msg_buffer} = '';
        $this->{_in_msg_buf_state} = AWAITING_HEADER_START;
        $this->{_in_msg_buf_bytes_exp} = 0;
        $this->{_in_msg_buf_type} = 0;
        $this->_enqueue_event(BGP_EVENT_RECEIVE_KEEP_ALIVE_MESSAGE);
    }
    else {
        $this->{_in_msg_buf_state} = AWAITING_MESSAGE_FRAGMENT;
        $this->{_in_msg_buf_bytes_exp} = $length - BGP_MESSAGE_HEADER_LENGTH;
        $this->{_in_msg_buf_type} = $type;
    }

    # indicate decoding and validation success
    return ( TRUE );
}

sub _encode_bgp_open_message
{
    my $this = shift();
    my ($buffer, $length);

    # encode optional parameters and length
    my $opt = '';

    if ($this->parent->support_capabilities) {

        if ( defined($this->{_peer_announced_id}) ) {
            # We received an open from the other end

            if ($this->{_peer_mbgp}) {
                $opt .= $this->_encode_capability_mbgp(1);
                $opt .= $this->_encode_capability_mbgp(2);
            }

            if ($this->{_peer_as4}) {
                $opt .= $this->_encode_capability_as4(1); #XXX
                $opt .= $this->_encode_capability_as4(2); #XXX
            }

        }  else {
            # We are sending the open

            if ( $this->parent->support_mbgp ) {
                $opt .= $this->_encode_capability_mbgp(1);
                $opt .= $this->_encode_capability_mbgp(2);
            }
            if ( $this->parent->this_can_as4 ) {
                $opt .= $this->_encode_capability_as4();
            }
	    if ( $this->parent->this_can_add_path ) {              
		$opt .= $this->_encode_capability_add_path(1); #XXX
		$opt .= $this->_encode_capability_add_path(2); #XXX
            }

        }

        # Both the standard (2) and Cisco (128) capabilities are sent
        if ($this->parent->this_can_refresh) {
            $opt .= $this->_encode_capability(BGP_CAPABILITY_REFRESH, '');
            $opt .= $this->_encode_capability(BGP_CAPABILITY_REFRESH_OLD, '');
        }
    }

    $buffer = pack('C', length($opt)) . $opt;

    # encode BGP Identifier field
    $buffer = inet_aton("127.0.0.1") . $buffer; #XXX

    # encode Hold Time
    $buffer = pack('n', $this->{_hold_time}) . $buffer;

    # encode local Autonomous System number
    if ($this->parent->this_as > 65535) {
        $buffer = pack('n', 23456) . $buffer;
    } else {
        $buffer = pack('n', $this->parent->this_as) . $buffer;
    }

    # encode BGP version
    $buffer = pack('C', $this->{_bgp_version}) . $buffer;

    return ( $this->_encode_bgp_message(BGP_MESSAGE_OPEN, $buffer) );
}

sub _encode_capability_mbgp
{
    my $this = shift;
    my $cap = shift;

    # Capability 1 with data of:
    # Address family 1 (IPv4), reserved bit 0, type 1 (unicast)
    my $cap = pack('ncc', $cap, 0, 1);
    my $opt = $this->_encode_capability(BGP_CAPABILITY_MBGP, $cap);

    return $opt;
}

sub _encode_capability_as4
{
    my $this = shift;

    # Capability 65 with data of the ASN
    my $cap = pack('N', $this->parent->this_as());
    my $opt = $this->_encode_capability(BGP_CAPABILITY_AS4, $cap);

    return $opt;
}

sub _encode_capability_add_path
{

    my $this = shift;
    my $afi = shift;

    # Capability 65 with data of the ASN
    my $cap = pack('n', $afi); # AFI
    $cap .= pack('c', 1); # SAFI
    $cap .= pack('c', 3); # send/receive
    my $opt = $this->_encode_capability(BGP_CAPABILITY_ADD_PATH, $cap);

    return $opt;
}

# Encodes a capability (inside the capability option)
# RFC5492
# Format is <2> <capability_len> <cap_code> <data_len>
sub _encode_capability
{
    my ($this, $type, $data) = @_;

    my $opt = '';
    $opt .= pack('C', BGP_OPTION_CAPABILITIES);    # Option Type

    my $cap = '';
    $cap .= pack('C', $type);                       # Capability Type
    $cap .= pack('C', length($data));               # Capability Data Len
    $cap .= $data;                                  # Capability data

    $opt .= pack('C', length($cap));                # Option Data Len
    $opt .= $cap;

    return $opt;
}

sub _decode_bgp_open_message
{
    my ($this, $buffer) = @_;
    my ($version, $as, $hold_time, $bgp_id);

    # decode and validate BGP version
    $version = unpack('C', substr($buffer, 0, 1));
    if ( $version != BGP_VERSION_4 ) {
        $this->_error(
            BGP_ERROR_CODE_OPEN_MESSAGE,
            BGP_ERROR_SUBCODE_BAD_VERSION_NUM,
            pack('n', BGP_VERSION_4)
        );
    }

    # decode and validate remote Autonomous System number
    $as = unpack('n', substr($buffer, 1, 2));
    if ( $as != $this->parent->peer_as ) {
        if ($this->parent->peer_as < 65536) {
            $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE,
                          BGP_ERROR_SUBCODE_BAD_PEER_AS);
        } elsif ($as != 23456) {
            $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE,
                          BGP_ERROR_SUBCODE_BAD_PEER_AS);
        }
    }

    # decode and validate received Hold Time
    $hold_time = _min(unpack('n', substr($buffer, 3, 2)), $this->{_hold_time});
    if ( ($hold_time < 3) && ($hold_time != 0) ) {
        $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE,
            BGP_ERROR_SUBCODE_BAD_HOLD_TIME);
    }

    # decode received BGP Identifier
    # Spelling error is retained for compatibility.
    $this->{_peer_annonced_id} = inet_ntoa(substr($buffer, 5, 4));
    $this->{_peer_announced_id} = inet_ntoa(substr($buffer, 5, 4));

    # decode known Optional Parameters
    my $opt_length = unpack('c', substr($buffer, 9, 1));
    my $opt = substr($buffer, 10, $opt_length);
    while ($opt ne '')
     {
      my ($type, $length) = unpack('cc', substr($opt, 0, 2));
      my $value = substr($opt, 2, $length);
      if ($type eq BGP_OPTION_CAPABILITIES)
       {
        $this->_decode_capabilities($value);
       }
      else
       { # Unknown optional parameter!
         # XXX We should send a notify here.
       }
      $opt = substr($opt, 2+$length);
     };

    # set Hold Time to negotiated value
    $this->{_hold_time} = $hold_time;

    # indicate decoding and validation success
    return ( TRUE );
}

# Capabilities we don't understand get ignored.
sub _decode_capabilities
{
    my ($this, $value) = @_;

    $this->{'_peer_refresh'} = TRUE;

    while (length($value) > 0) {

        if (length($value) < 2) {
            $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE,
                BGP_ERROR_SUBCODE_BAD_OPT_PARAMETER);
            return;
        }

        my ($type, $len) = unpack('cc', substr($value, 0, 2));
        my $data = substr($value, 2, $len);

        $this->_decode_one_capability($type, $len, $data);

        $value = substr($value, 2+$len);
    }

}

sub _decode_one_capability {
    my ($this, $type, $len, $data) = @_;

    if (length($data) != $len) {
        $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE,
            BGP_ERROR_SUBCODE_BAD_OPT_PARAMETER);
    }

    if ($type == BGP_CAPABILITY_MBGP) {
        $this->{_peer_mbgp} = TRUE;
    }

    if ($type == BGP_CAPABILITY_REFRESH) {
        $this->{_peer_refresh} = TRUE;
    }
    if ($type == BGP_CAPABILITY_REFRESH_OLD) {
        $this->{_peer_refresh} = TRUE;
    }

    if ($type == BGP_CAPABILITY_AS4) {

        if ($len != 4) {
            $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE,
                BGP_ERROR_SUBCODE_BAD_OPT_PARAMETER);
        }
   
        my $as = unpack('N', $data); 
        if ($as != $this->parent->peer_as) {
            $this->_error(BGP_ERROR_CODE_OPEN_MESSAGE,
                BGP_ERROR_SUBCODE_BAD_PEER_AS);
        }

        # Both ends must support this. 
        if ( $this->parent->this_can_as4 ) {
            $this->{_peer_as4} = TRUE;
        }
    }

}

sub _decode_bgp_notification_message
{
    my ($this, $buffer) = @_;
    my ($error, $error_code, $error_subcode, $data);

    # decode and validate Error code
    $error_code = unpack('C', substr($buffer, 0, 1));
    if ( ($error_code < 1) || ($error_code > 6) ) {
        die("_decode_bgp_notification_message(): invalid error code = $error_code\n");
    }

    # decode and validate Error subcode
    $error_subcode = unpack('C', substr($buffer, 1, 1));
    if ( ($error_subcode < 0) || ($error_subcode > 11) ) {
        die("_decode_bgp_notification_message(): invalid error subcode = $error_subcode\n");
    }

    # decode Data field
    $data = substr($buffer, 2, length($buffer) - 2);

    return Net::BGP::Notification->new(
        ErrorCode => $error_code,
        ErrorSubcode => $error_subcode,
        ErrorData => $data);
}

sub _encode_bgp_keepalive_message
{
    my $this = shift();
    return ( $this->_encode_bgp_message(BGP_MESSAGE_KEEPALIVE) );
}

sub _encode_bgp_update_message
{
    my ($this, $buffer) = @_;
    return ( $this->_encode_bgp_message(BGP_MESSAGE_UPDATE, $buffer) );
}

sub _encode_bgp_refresh_message
{
    my ($this, $buffer) = @_;
    return ( $this->_encode_bgp_message(BGP_MESSAGE_REFRESH, $buffer) );
}

sub _encode_bgp_notification_message
{
    my ($this, $error_code, $error_subcode, $data) = @_;
    my $buffer;

    # encode the Data field
    $buffer = $data ? $data : '';

    # encode the Error Subcode field
    $buffer = pack('C', $error_subcode) . $buffer;

    # encode the Error Code field
    $buffer = pack('C', $error_code) . $buffer;

    return ( $this->_encode_bgp_message(BGP_MESSAGE_NOTIFICATION, $buffer) );
}

## POD ##

=pod

=head1 NAME

Net::BGP::Transport - Class encapsulating BGP-4 transport session state and functionality

=head1 SYNOPSIS

    use Net::BGP::Transport;

    $trans = Net::BGP::Transport->new(
        Start                => 1,
	Parent               => Net::BGP::Peer->new(),
        ConnectRetryTime     => 300,
        HoldTime             => 60,
        KeepAliveTime        => 20
    );

    $version = $trans->version();

    $trans->start();
    $trans->stop();

    $trans->update($update);
    $trans->refresh($refresh);


=head1 DESCRIPTION

This module encapsulates the state and functionality associated with a BGP
transport connection. Each instance of a Net::BGP::Transport object
corresponds to a TCP session with a distinct peer. It should not be used by
it self, but encapsulated in a Net::BGP::Peer object.

=head1 CONSTRUCTOR

=over 4

=item new() - create a new Net::BGP::Transport object

This is the constructor for Net::BGP::Transport objects. It returns a
reference to the newly created object. The following named parameters may
be passed to the constructor. Once the object is created, the information
can not be changed.

=over 4

=item Start

=item ConnectRetryTime

=item HoldTime

=item KeepAliveTime

Has the same meaning as their equivalente named argument for Net::BGP::Peer.

=item Parent

The parent Net::BGP::Peer object.

=back

=item renew() - fetch the existing Net::BGP::Peer object from the "object string".

This "reconstructor" returns a previeus constructed object from the
perl genereted string-context scalar of the object, eg.
I<Net::BGP::Peer=HASH(0x820952c)>.

=back

=head1 ACCESSOR METHODS

=over 4

=item version()

=item start()

=item stop()

=item update()

=item refresh()

=item is_established()

This methods does the actuall I<work> for the methods of the same name in
Net::BGP::Peer.

=back

=head1 SEE ALSO

Net::BGP::Peer, Net::BGP, Net::BGP::Update, Net::BGP::Refresh

=head1 AUTHOR

Stephen J. Scheck <code@neurosphere.com> in original Peer.pm form
Martin Lorensen <lorensen@cpan.org> seperated into Transort.pm

=cut

## End Package Net::BGP::Transport ##

1;
