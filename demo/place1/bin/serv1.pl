#!/usr/bin/perl -w

#  $Id: serv1.pl,v 1.7 2001/04/10 13:05:22 aigan Exp $  -*-perl-*-

#=====================================================================
#
# DESCRIPTION
#   CGI server for places records
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2000-2001 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

use 5.006;
use strict;
use POSIX;
use IO::Socket 1.18;
use IO::Select;
use Socket;
use Data::Dumper;
use Carp;
use Time::HiRes qw( time );
use CGI;
use Template 2;
use FreezeThaw qw( thaw );

# TODO: use FindBin;
# use FindBin; use lib $FindBin::Bin; # Gives tainted data!

use lib "../../../lib";

use Wraf::Result;
use RDF::Service;
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( $Level debug debug_start debug_end
			    get_unique_id reset_level time_string
			    $DEBUG );

our $version = $RDF::Service::VERSION;
$version =~ s/\./_/;

our $q = undef;
our $s = undef;

our $th = Template->new(
      INTERPOLATE => 1,
      INCLUDE_PATH => 'tmpl',
      PRE_PROCESS => 'header',
      POST_PROCESS => 'footer',
      FILTERS =>
      {
	  'uri' => sub { CGI::escape($_[0]) },
      }
     );


our $client; #The current client
$SIG{PIPE} = 'IGNORE';


{
    my $port=7788;

    # Set up the tcp server. Must do this before chroot.
    my $server= IO::Socket::INET->new(
	  LocalPort => $port,
	  Proto => 'tcp',
	  Listen => 10,
	  Reuse => 1,
	 ) or (die "Cannot connect to socket $port: $@\n");

    print("Connected to port $port.\n");


    my %inbuffer=();
    my %length=();
    NonBlock($server);
    my $select=IO::Select->new($server);

    print("Setup complete, accepting connections.\n");

    open STDERR, ">/tmp/RDF-Service-$version.log" or die $!;

  main_loop:
    while (1)
    {
	# The algorithm was adopted from perlmoo by Joey Hess
	# <joey@kitenet.net>.



	#    warn "...\n";
	#    my $t0 = [gettimeofday];

	my $rv;
	my $data;

	# See if clients have sent any data.
	#    my @client_list = $select->can_read(1);
	#    print "T 1: ", tv_interval ( $t0, [gettimeofday]), "\n";

      WAITING:
	foreach $client ($select->can_read(5))
	{
	    if ($client == $server)
	    {
		# New connection.
		my($iaddr, $address, $port, $peer_host);
		$client = $server->accept;
		if(!$client)
		{
		    warn("Problem with accept(): $!");
		    next;
		}
		($port, $iaddr) = sockaddr_in(getpeername($client));
		$peer_host = gethostbyaddr($iaddr, AF_INET) || inet_ntoa($iaddr);
		$select->add($client);
		NonBlock($client);

		warn "\n\nNew client connected\n" if $DEBUG > 3;
	    }
	    else
	    {
		# Read data from client.
		$data='';
		$rv = $client->recv($data,POSIX::BUFSIZ, 0);

		warn "Read data...\n" if $DEBUG > 3;

		unless (defined $rv && length $data)
		{
		    # EOF from client.
		    CloseCallBack('eof');
		    warn "End of file\n";
		    next;
		}

		$inbuffer{$client} .= $data;
		unless( $length{$client} )
		{
		    warn "Length of record?\n" if $DEBUG > 3;
		    # Read the length of the data string
		    #
		    if( $inbuffer{$client} =~ s/^(\d+)\x00// )
		    {
			warn "Setting length to $1\n" if $DEBUG > 3;
			$length{$client} = $1;
		    }
		}

		if( $length{$client} )
		{
		    warn "End of record?\n" if $DEBUG > 3;
		    # Have we read the full record of data?
		    #
		    if( length $inbuffer{$client} >= $length{$client} )
		    {
			warn "The whole length read\n" if $DEBUG > 3;
			handle_request( $client, \$inbuffer{$client} );
			$inbuffer{$client} = '';
			$length{$client} = 0;
			CloseCallBack();
		    }
		}
	    }
	}
    }



    sub NonBlock
    {
	my $socket=shift;

	# Set a socket into nonblocking mode.  I guess that the 1.18
	# defaulting to autoflush makes this function redundant

	use Fcntl;
	my $flags= fcntl($socket, F_GETFL, 0) 
	  or die "Can't get flags for socket: $!\n";
	fcntl($socket, F_SETFL, $flags | O_NONBLOCK)
	  or die "Can't make socket nonblocking: $!\n";
    }

    sub CloseCallBack
    {
	my( $reason ) = @_;

	# Someone disconnected or we want to close the i/o channel.

	delete $inbuffer{$client};
	$select->remove($client);
	close($client);
    }
}

sub handle_request
{
    my( $client, $recordref ) = @_;

    my( $value ) = thaw( $$recordref );
    $q    = $value->[0];
    %ENV = @{$value->[1]};

    # We can't have the CGI module trying to read POST data
    $ENV{'REQUEST_METHOD'} = 'GET';

    my( $me ) = $ENV{'SCRIPT_NAME'} =~ m!/([^/]+)$!;


    if( $DEBUG > 8 )
    {
	$client->send( $q->header );
	$client->send( "<h1>Got something!</h1>" );
	$client->send("<plaintext>\n");
	foreach my $key ( $q->param() )
	{
	    my $value = $q->param($key);
	    $value =~ s/\x00/?/g;
	    $client->send("   $key:\t$value\n");
	}
    }


    warn "Constructing RDF::Service object\n" if $DEBUG;
    my $offset = &dlines();
    my $result = new Wraf::Result;
    my $s_cookie = $q->cookie('wraf_session');
    $Level = 0;
    $s = &get_session( $s_cookie );
    unless( $s )
    {
	print $client "Content-type: text/html\n\n";
	print $client "<html><body><p><strong>Cookies must ".
	  "be enabled! Try to reload this page...".
	    "</strong></p></body></html>";
	return;
    }


    my $params =
    {
	'cgi'      => $q,
	'me'       => $me,
	'result'   => $result,
	'ENV'      => \%ENV,
	'VERSION'  => $RDF::Service::VERSION,
	's'        => $s,

	'NS_LS'    => NS_LS,
	'NS_LD'    => NS_LD,
	'NS_RDF'   => NS_RDF,
	'NS_RDFS'  => NS_RDFS,
	'NS_DAML'  => NS_DAML,

	'lit'     => sub { \$_[0] },
	'unique'  => \&unique,
	'dump'    => \&Dumper,
	'reset'   => \&reset_level,
	'offset'  => $offset,
	'dlines'  => \&dlines,
        'warn'    => sub { debug "NOTE: $_[0]\n", 1; '' },
    };


    # Performe the actions (anything that changes the database)
    #
    my $action = $q->param('action');
    if( $action )
    {
	$action = 'do_'.$action;
	eval
	{
	    no strict 'refs';
	    debug_start($action, '+', $s);
	    $result->message( &{$action}() );
	    debug_end($action, '+', $s);
	    ### Other info is stored in $result->{'info'}
	    1;
	}
	or $result->exception($@);
    }


    # Set the handler depending of the action result
    #
    my $handler = "";
    $handler = $q->param('previous') if $result->{'error'};
    $handler ||= ($q->param('handler')||'main');
    $params->{'handler'} = $handler;
    warn "Porcessing template $handler\n" if $DEBUG > 3;


    # Construct and return the response (handler) page
    #
    warn "\n********************\n".
      "*** Returning page\n".
	"********************\n\n" if $DEBUG;
    $Level = 0;
    $client->print( $q->header );
    my $handler_file = $handler; #.'.html';
    $th->process($handler_file, $params, $client)
      or do
      {
	  &reset_level;
	  warn "Oh no!\n" if $DEBUG; #Some error sent to browser
	  my $error = $th->error();
	  if( ref $error )
	  {
	      $result->error($error->type(),
			     $error->info()
			    );
	  }
	  else
	  {
	      $result->error('funny', $error);
	  }
	  $th->process('error', $params, $client)
	    or die( "Fatal template error: ".
		      $th->error()."\n");
      };


    warn "Done!\n\n" if $DEBUG;
}

sub get_session
{
    my( $session_key ) = @_;

    our %session_cache;

    return undef unless $session_key;

    if( $session_cache{$session_key} )
    {
	warn "Found old session $session_key\n" if $DEBUG;
	return $session_cache{$session_key};
    }
    else
    {
	warn "New session $session_key\n" if $DEBUG;
	$session_key =~ s/[^\w\-\.]//g;

	$session_key = $q->param('s') if $q->param('s');

	my $session = new RDF::Service( NS_LD."service/$session_key" );

	$session->connect("RDF::Service::Interface::DBI::V01",
			{
			    connect => "dbi:Pg:dbname=wraf_v01a",
			    name =>    "wwwdata",
			});
	$session->connect("RDF::Service::Interface::HTML_Forms");

	$session->set_abbrev(
	    {
		Lodging     => NS_LD.'Class/Lodging',
		agent       => NS_LS.'agent',
		updated     => NS_LS.'updated',
		label       => NS_RDFS.'label',
		subClassOf  => NS_RDFS.'subClassOf',
		place_query => NS_LD.'place_query',
		pred        => NS_RDF.'predicate',
		subj        => NS_RDF.'subject',
		obj         => NS_RDF.'object',
	    });


	# Initialize the session metadata
	#
	$session->init_rev_subjs;
	unless( $session->exist_pred( NS_LS.'updated' ) )
	{
	    $session->set_props(
		{ NS_LS.'updated' => [ \ (time_string()) ] }, 2 );
	}

	unless( $session->exist_pred( NS_LD.'place_query' ) )
	{
	    # Must initiate DB if necessary
	    my $cPquery = $session->get(NS_LD.'Place_query');
	    unless( $cPquery->is_a(NS_RDFS.'Class') )
	    {
		# TODO: Should rather prospone call to later...
		$s = $session;
		&do_initiate_db;
	    }

	    # Create a new query instance
	    my $ciPquery = $session->get->set([$cPquery]);
	    $session->declare_add_prop(NS_LD.'place_query', $ciPquery );
	}


	return $session_cache{$session_key} = $session;
    }
}

########  Action functions  #########################

sub do_initiate_db
{
    my $model = $s->get_model(NS_LD.'M1');

    my $ns_Lodging = NS_LD.'Class/Lodging';
    my $ns_form = NS_LS.'Form';

    my $true = $s->get(NS_LS.'True');
    my $cClass = $s->get( NS_RDFS.'Class' );

    my $cLodging = $model->get($ns_Lodging)->set( [$cClass] );

    $model->get($ns_Lodging.'/Hotel')->set(
	  [$cClass],
	{
	    subClassOf => $cLodging,
	    label      => \"Hotell",
	});

    $model->get($ns_Lodging.'/Hostel')->set(
	  [$cClass],
	{
	    subClassOf => $cLodging,
	    label      => \"Vandrarhem",
	});

    $model->get($ns_Lodging.'/Castle')->set(
	  [$cClass],
	{
	    subClassOf => $cLodging,
	    label      => \"Slott",
	});

    $model->get($ns_Lodging.'/Campsite')->set(
	  [$cClass],
	{
	    subClassOf => $cLodging,
	    label      => \"Campingplats",
	});

    $model->get(NS_LD.'Place_query')->set(
	  [$cClass],
	{
	    label      => \"Place query",
	    subClassOf => NS_LS.'Query',
	});

    $model->get(NS_LD.'Form/lodging_type_list')->set(
	  ["$ns_form/Widget/SubContainer"],
	{
	    "$ns_form/field_type" => NS_RDFS.'Container',
	    "$ns_form/trim_value" => $true,
	    "$ns_form/remove_if_empty" => $true,
	    "$ns_form/connection" => NS_DAML.'unionOf',
	});

    return "DB initiated";
}

sub do_query
{
    return &do_state( 1, "Query recieved" );
}

sub do_state
{
    my( $solid, $message ) = @_;

    my $model = $s->get_model(NS_LD.'Model/a1');

    my $r_focus = $q->param('focus') or die "No focus specified";
    my $focus = $model->get($r_focus);
    debug "  Focus set to $focus->[NODE][URISTR]\n";

    # TODO: Validate data

    ### Calling widgets by name
    no strict 'refs';

    foreach my $param ($q->param)
    {
	my( $dir, @args ) = split / /, $param;
	next unless @args; # Maby just a meta-element
	my $val = [$q->param($param)];

	# The format is a_b-c there a and b are parameters and c is
	# the format of the value, if not an ordinary object.  The
	# set_ functions will substitute '-' for '_' to make it a
	# valid funtion name.

	$dir =~ s/-/_/;
	$dir = 'fe_'.$dir;

	debug_start($dir, '+', $focus);
	$message .= &{$dir}($focus, \@args, $val, $solid );
	debug_end($dir, '+', $focus);
    }

    $message ||= "Stating focus stored";

    $focus->store;

    return $message;
}

#########  Form elements  #######################

sub fe_pred_lit
{
    my( $self, $args, $vals, $solid ) = @_;
    my $pred = $args->[0];

    $pred = $self->get($pred);

    foreach my $lit_str ( @$vals )
    {
	$self->declare_add_prop( $pred, \$lit_str, undef, undef, $solid );
    }

    return '';
}

sub fe_pred
{
    my( $self, $args, $vals, $solid ) = @_;
    my( $pred ) = @$args;

    $pred = $self->get($pred);

    foreach my $obj ( @$vals )
    {
	$self->declare_add_prop( $pred, $obj, undef, undef, $solid );
    }

    return '';
}

sub fe_subj_pred
{
    my( $self, $args, $vals, $solid ) = @_;
    my( $subj, $pred ) = @$args;

    $subj = $self->get($subj);
    $pred = $self->get($pred);

    foreach my $obj ( @$vals )
    {
	$subj->declare_add_prop( $pred, $obj, undef, undef, $solid );
    }

    return '';
}

sub fe_li
{
    my( $self, $args, $vals, $solid ) = @_;
    my( $cont ) = @$args;

    debug "  (@$vals)\n";

    $cont = $self->get($cont);
    # TODO: Check that $cont is a container
    # TODO: Handle $solid

    my $selection = $cont->[NODE][SELECTION];
    foreach my $obj ( @$vals )
    {
	push @$selection, $self->get_node($obj);
    }

    # Expire CONTENT_ALL
    $cont->[NODE][CONTENT_ALL] = 0;

    return '';
}

sub fe_a
{
    my( $self, $args, $vals, $solid ) = @_;
    my( $widget ) = @$args;

    $widget = $self->get($widget);

    ### Call widget handler

    $widget->parse_data( $self, $vals, $solid );
    return '';
}


#####################################

sub dlines
{
    open FILE, "/tmp/RDF-Service-$version.log" or die $!;

    use Fcntl;
    our $llines = 0;
    our $loffset = 0;

    unless( seek FILE, $loffset, SEEK_SET )
    {
	$llines = 0;
	$loffset = 0;
    }
    while( <FILE> )
    {
	$llines++;
	$loffset += length;
    }
    close FILE;
    return $llines;
}

sub unique
{
    my( $base ) = @_;

    return $base . get_unique_id();
}

