#  $Id: HTML_Forms.pm,v 1.3 2001/04/11 16:51:21 aigan Exp $  -*-perl-*-

package RDF::Service::Interface::HTML_Forms;

#=====================================================================
#
# DESCRIPTION
#   Interface to handling data from HTML forms
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
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( save_ids uri2id debug time_string
			    $DEBUG debug_start debug_end id2uri
			    validate_context );
use URI;
use Data::Dumper;
use Carp qw( confess carp cluck croak );

use constant NS_FORM => NS_LS.'Form/';

sub register
{
    my( $interface ) = @_;

    # TODO: init_rev_objs

    return
    {
	'' =>
	{
	    'methods' =>
	    {
		NS_FORM.'Widget/SubContainer' =>
		{
		    parse_data => [\&parse_SubContainer],
		},
	    },
	    'preds' =>
	    {
	    },
	},
    };
}


sub not_implemented { die "not implemented" }

# TODO: Remove this, but without fatal results
sub noop {0,0} # Do nothing and continue


sub parse_SubContainer
{
    my( $self, $i, $focus, $vals, $solid ) = @_;

    # Get connection
    #
    my $connection = $self->arc_obj_list(NS_FORM.'connection')->[0]
      or die "No connection for widget $self->[NODE][URISTR]";
    debug "The connection is $connection->[NODE][URISTR]\n";

    # Should the value be trimmed?
    #
    my $trim_values = 0;
    $trim_values = 1 if $self->arc_obj_list(NS_FORM.'trim_value')->[0];

    # Remove if empty?
    #
    my $remove_if_empty = 0;
    $remove_if_empty = 1 if $self->arc_obj_list(NS_FORM.'remove_if_empty')->[0];

    # Field type
    #
    my $field_type = $self->arc_obj_list(NS_FORM.'field_type')->[0]
      or die "No field_type for widget $self->[NODE][URISTR]";


    # Locate existing container
    #
    my $arc = $focus->arc({ pred => $connection,
			    obj =>
			    {
				NS_FORM.'controlled_by' => $self,
			    }
			   })->list->[0];

    my $container = $arc ? $arc->obj :undef;

#     foreach my $cont_arc ( @{$focus->arc($connection)->list} )
#     {
# 	# Is this object contolled by this widget?  TODO: Do not
# 	# assume that each subcontainer is only controlled by one
# 	# widget
# 	my $cont = $cont_arc->obj;
# 	my $controller = $cont->arc_obj_list(NS_FORM.'controlled_by')->[0];
# 	if( $controller->[NODE][URISTR]	eq $self->[NODE][URISTR] )
# 	{
# 	    $container = $cont;
# 	    $arc = $cont_arc;
# 	}
#     }

    if( $container )
    {
	my $cont_node = $container->[NODE];
	my $container_changed = 0;

	debug "container found: $cont_node->[URISTR]\n";

	#Trim values?
	if( $trim_values )
	{
	    debug "Removing existing content\n";
	    # TODO: Maby only change what is diffrent
	    $cont_node->[SELECTION] = [];
	    $container_changed ++;
	}

	# Fill values
	debug "Adding ".scalar(@$vals)." entries".
	      "to $container->[NODE][URISTR]\n";
	my $selection = $cont_node->[SELECTION];
	foreach my $obj ( @$vals )
	{
	    debug "  Adding $obj\n";
	    push @$selection, $self->get_node($obj);
	    $container_changed ++;
	}

	# Remove arc if selection empty
	if( @$selection )
	{
	    $container->changed('selection') if $container_changed;
	}
	else
	{
	    debug "No content. Removing arc\n";
	    $container->delete_node;
	    $arc->delete_node;
	}
    }
    else
    {
	# Do not do anything if no values selected
	if( @$vals )
	{
	    debug "Creating new container\n";

	    # Create container
	    $container = $self->get->set(
		  [$field_type],
		{
		    NS_FORM.'controlled_by' => $self,
		});

	    # Fill values
	    debug "Adding ".scalar(@$vals)." entries ".
	      "to $container->[NODE][URISTR]\n";
	    my $selection = $container->[NODE][SELECTION];
	    foreach my $obj ( @$vals )
	    {
		debug "  Adding $obj\n";
		push @$selection, $self->get_node($obj);
	    }
	    # Content changed. Has to do this!
	    $container->[NODE][CONTENT_ALL] = 0;  ## Or???

	    # Create arc
	    $focus->declare_add_prop( $connection, $container,
				      undef, undef, $solid );
	}
    }
    return( 1, 3 );
}



1;
