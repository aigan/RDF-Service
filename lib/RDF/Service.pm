#  $Id: Service.pm,v 1.32 2001/03/14 13:39:04 aigan Exp $  -*-perl-*-

package RDF::Service;

#=====================================================================
#
# DESCRIPTION
#   Creates the Service resource
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

use strict;
use 5.006;
use RDF::Service::Constants qw( :rdf :namespace :context );
use RDF::Service::Cache qw( get_unique_id uri2id debug debug_start
			    debug_end time_string $DEBUG);
use RDF::Service::Resource;
use RDF::Service::Context;
use Data::Dumper;

our $VERSION = 0.0454;

sub new
{
    my( $class, $uristr ) = @_;

    # Initialize the level indicator
    $RDF::Service::Cache::Level = 0;

    debug_start("new RDF::Service");

    if( $uristr )
    {
	# Must have a Service URI as recognized by the Base find_node

	my $pattern = "^".NS_LD."service/[^/#]+\$";
	unless( $uristr =~  m/$pattern/o )
	{
	    die "Invalid namespace for Service: $uristr not matching $pattern";
	}
    }
    else
    {
	# Every service object is unique
	#
	$uristr = NS_LD."service/".&get_unique_id;
    }


    # The service object is not stored in any interface.  The base
    # interface init_types function states that all resources matching
    # a specific pattern are Service objects.  That is needed since
    # the resources acts as models for other models stored in other
    # interfaces.  But here we state the types for the newly created
    # Service object.

    # Declare the types for the service.  Do it the low-level way.  We
    # can not call declare_add_typews() since that calles init_props()
    # for the classes.


    my $so = RDF::Service::Resource->new($uristr);
    $so->[RUNLEVEL] = 0; # Startup runlevel
    my $s = RDF::Service::Context->new( $so, {} );
    $s->[SESSION] = $so;

    debug "  Node    is $so\n", 2;
    debug "  Session is $s->[SESSION]\n", 2;

    &_bootstrap( $s );

    debug_end("new RDF::Service");

    return $s;
}

sub _bootstrap
{
    my( $s ) = @_;
    #
    # Connect the base interface.

    debug_start( "_bootstrap", " ", $s);

    my $node = $s->[NODE];

    my $base_model = $s->get_node(NS_LS.'The_Base_Model');
#    $base_model->[REV_MODEL]{$node->[ID]} = $node;  # Try without...
    $base_model->[TYPE_ALL] = 1;
    debug "Changing SOLID to 1 for $base_model->[URISTR] ".
      "IDS $base_model->[IDS]\n", 3;
    $base_model->[SOLID] = 1; # nonchanging

    $s->[WMODEL] = $s;
    $node->[MODEL] = $base_model;
    $node->[TYPE] = {};
    $node->[INTERFACES] = [];
    debug "Changing SOLID to 0 for $node->[URISTR] ".
      "IDS $node->[IDS]\n", 3;
    $node->[SOLID] = 0;

    my $module = "RDF::Service::Interface::Base::V01";

    my $file = $module;
    $file =~ s!::!/!g;
    $file .= ".pm";
    require "$file";

    {
	no strict 'refs';
#	my $base_interface_uri = &{$module."::_construct_interface_uri"}( $module );
#	my $base_interface = $s->get( $base_interface_uri );

	# NB! The session node is used as the interface.  It will be
	# replaced during the connection.
	#
	debug_start( "connect", 0, $s );
	&{$module."::connect"}( $s, $s->[NODE], $module );
	debug_end( "connect", 0, $s );
    }

    # Node has now been updated
    #
    $node = $s->[NODE];

    # The IDS of $s is now defined; update $s->[WMODEL].  We do not
    # have to do the same thing for $node, since it doesn't is used as
    # an object above.
    #
    $base_model->[IDS] = $node->[IDS];
    $base_model->[JUMPTABLE] = undef;
    $base_model->[DYNTABLE] = undef;


    # Add the type
    #
    $s->declare_add_types( [NS_LS.'Service'] );

    $node->[RUNLEVEL] = 1; # Normal runlevel


    debug_end( "_bootstrap", " ", $s);
}


1;

