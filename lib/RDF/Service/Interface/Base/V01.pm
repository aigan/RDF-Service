#  $Id: V01.pm,v 1.40 2001/04/11 16:51:21 aigan Exp $  -*-perl-*-

package RDF::Service::Interface::Base::V01;

#=====================================================================
#
# DESCRIPTION
#   Interface to the basic Resource actions
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
		NS_LS.'Service' =>
		{
		    'connect'    => [\&connect],
		    'find_node'  => [\&find_node], ### DEPRECATED
		    'set_abbrev' => [\&set_abbrev],
		},
		NS_RDFS.'Container' =>
		{
		    'sel'       => [\&sel],
		    'li'        => [\&li],
		    'list'      => [\&list],
		},
		NS_LS.'Model' =>
		{
#		    'create_model'    => [\&create_model], ## MOVED
#		    'validate'        => [\&not_implemented],
		},
		NS_RDFS.'Literal' =>
		{
		    'desig' => [\&desig_literal],
		    'value' => [\&value],
		},
		NS_RDF.'Statement' =>
		{
		    # TODO: Rename pred to pred_li as to not conflict
		    # with abbrev
		    'pred' => [\&pred],
		    'subj' => [\&subj],
		    'obj'  => [\&obj],
		    'desig' => [\&desig_statement],
		    'get_multi_arc' => [\&get_multi_arc],
		},
		NS_RDFS.'Resource' =>
		{
		    'desig'               => [\&desig_resource],
		    'delete_node_cascade' => [\&delete_node_cascade],
		    'delete_node'         => [\&delete_node],
		    'init_src_types'      => [\&noop],
		    'init_dyn_types'      => [\&noop],
		    'init_src_rev_subjs'  => [\&noop],
		    'store_types'         => [\&noop],
		    'remove_types'        => [\&noop],
		    'store_node'          => [\&noop],
		    'store_props'         => [\&noop],
		},
		NS_RDFS.'Class' =>
		{
		    'init_dyn_rev_types'      => [\&init_dyn_rev_types],
		},
	    },
	    'preds' =>
	    {
		NS_RDFS.'Container' =>
		{
#		    NS_LS.'is_empty'  => [\&not_implemented],
		    NS_LS.'size'      => [\&reset_size],
		},
		NS_LS.'Model' =>
		{
		    # The NS. The base for added things...
#		    NS_LS.'source_uri'=> [\&not_implemented],

		    # is the model open or closed?
#		    NS_LS.'is_mutable'=> [\&not_implemented],
		},
		NS_RDF.'Statement' =>
		{
#		    NS_RDF.'predicate'  => [\&not_implemented],
#		    NS_RDF.'subject'    => [\&not_implemented],
#		    NS_RDF.'object'     => [\&not_implemented],
		},
		NS_RDFS.'Class' =>
		{
		    NS_LS.'level'         => [\&reset_level],
		    NS_RDFS.'subClassOf'  => [\&reset_subClassOf],
		},
	    },
	},
	NS_LD."service/" =>
	{
	    'methods' =>
	    {
		NS_RDFS.'Resource' =>
		{
		    'init_src_types'     => [\&init_types_service],
		    'init_dyn_types'     => [\&noop],
		    'init_src_rev_subjs' => [\&init_rev_subjs],
		},
	    },
	},
	NS_LD."literal/" =>
	{
	    'methods' =>
	    {
		NS_RDFS.'Resource' =>
		{
		    'init_src_types'     => [\&init_types_literal],
		    'init_dyn_types'     => [\&noop],
		    'init_src_rev_subjs' => [\&init_rev_subjs],
		},
	    },
	},
	&NS_LS =>
	{
	    'methods' =>
	    {
		NS_RDFS.'Resource' =>
		{
		    'init_src_types'     => [\&init_types_base],
		    'init_dyn_types'     => [\&noop],
		    'init_src_rev_subjs' => [\&init_rev_subjs],
		},
	    },
	},
	&NS_RDF =>
	{
	    'methods' =>
	    {
		NS_RDFS.'Resource' =>
		{
		    'init_src_types'     => [\&init_types_base],
		    'init_dyn_types'     => [\&noop],
		    'init_src_rev_subjs' => [\&init_rev_subjs],
		},
	    },
	},
	&NS_RDFS =>
	{
	    'methods' =>
	    {
		NS_RDFS.'Resource' =>
		{
		    'init_src_types'     => [\&init_types_base],
		    'init_dyn_types'     => [\&noop],
		    'init_src_rev_subjs' => [\&init_rev_subjs],
		},
	    },
	},
    };
}



# ??? Create literal URIs by apending '#val' to the statement URI

sub not_implemented { die "not implemented" }

# TODO: Remove this, but without fatal results
sub noop {0,0} # Do nothing and continue

sub connect
{
    my( $self, $i, $module, $args ) = @_;

    # Create the interface object. The IDS will be the same for the
    # RDF object and the new interface object.  Old interfaces doesn't
    # get their IDS changed.

    # A Interface is a source of statements. The interface also has
    # special metadata, as the type of interface, its range, etc.  The
    # main property of the interface is its model that represents all
    # the statements.  The interface can also have a collection of
    # literals, namespaces, resource names and other things.


    # Create the new interface resource object
    #
    my $uri = _construct_interface_uri( $module, $args );
    my $node = $self->[NODE];



    if( $DEBUG >= 5 )
    {
	debug "Nodes in this IDS:\n";
	foreach my $id ( keys %{$self->[WMODEL][NODE][REV_MODEL]} )
	{
	    my $obj = $self->get_context_by_id($id);
	    debug "  $id: ".$obj->desig."\n";
	}
    }

    # Generate new IDS
    #
    my $new_ids = join('-', map(uri2id($_->[URISTR]),
				@{$node->[INTERFACES]}),
		       uri2id($uri));

    # Initialize the cache for this IDS.  Each IDS has it's own cache
    # of node objects
    #
    $RDF::Service::Cache::node->{$new_ids} ||= {};

    # Update IDS and export model resources to new IDS
    #
    _export_to_ids( $self, $i, $node, $new_ids );



    # A new Service node should now have been created.  Make $self
    # point to the new node.  Change the IDS in order to get it from
    # the right IDS cache.  Kill the old node!
    #
    my $new_node = $self->get_node_by_id( $node->[ID], $new_ids );
    $self->[NODE] = $new_node;
    my $new_wmodel =
      $self->get_context_by_id( $self->[WMODEL][NODE][ID], $new_ids );
    $self->[WMODEL] = $new_wmodel;
    $self->[SESSION] = $self->get_node_by_id( $node->[ID], $new_ids );

#    debug "*!* New NODE has now IDS $self->[NODE][IDS]\n";
#    debug "*!* Setting new WMODEL to IDS $new_wmodel->[NODE][IDS]\n";
    $new_node->[INTERFACES] = $node->[INTERFACES];
    $node = undef;



    # Create a new base model
    #
    my $base_model = $self->get_node(NS_LS.'The_Base_Model', $new_ids);
    $base_model->[TYPE_ALL] = 1;
    debug "Changing SOLID to 1 for $base_model->[URISTR] ".
      "IDS $base_model->[IDS]\n", 3;
    $base_model->[SOLID] = 1; # nonchanging
    $new_node->[MODEL] = $base_model;
    $base_model->[REV_MODEL]{$new_node->[ID]} = $new_node;

    # This should get the new *interface* node prepared by _export_to_ids
    #
    my $new_interface = $self->get( $uri, $new_ids );
    my $new_interface_node = $new_interface->[NODE];

    push @{$new_node->[INTERFACES]}, $new_interface_node;
    save_ids( $new_ids, $new_node->[INTERFACES] );

    # Set up the new object, based on the IDS
    #
    my $ninm = $self->[WMODEL][NODE]; # What is the model of this?
    $new_interface_node->[MODEL] = $ninm;
    $self->[WMODEL][NODE][REV_MODEL]{$ninm->[ID]} = $ninm;
    $new_interface_node->[MODULE_NAME] = $module; # This is not used


    # OBS: The TYPE creation must wait. The type object depends on the
    # RDFS interface object in the creation. So it can't be set until
    # the RDFS interface has been created. The TYPE value will be set
    # then needed.

    # This is the functions offered by the interface. Pass on the
    # interface initialization arguments.
    #
    my $file = $module;
    $file =~ s!::!/!g;
    $file .= ".pm";
    require "$file" or die $!;


    debug "Registring $file\n", 1;

  {   no strict 'refs';
      $new_interface_node->[MODULE_REG] =
	&{$module."::register"}( $new_interface_node, $args );
  }

    return( $new_interface, 1 );
}

sub set_abbrev
{
    my( $self, $i, $abbrevs ) = @_;

    # Reset previous data
    $self->[NODE][ABBREV] = {};

#    debug "  Self    is $self->[NODE]\n", 2;
#    debug "  Session is $self->[SESSION]\n", 2;

    foreach my $abbrev ( keys %$abbrevs )
    {
	debug "Setting abbrevation $abbrev\n", 2;

	my $pred = $abbrevs->{$abbrev};
	$pred = $self->get( $pred ) unless ref $pred;

	$self->[NODE][ABBREV]{$abbrev} = $pred;
    }

#    debug "Abbrevations:\n".Dumper($self->[SESSION][ABBREV])."\n", 2;

    return( 1,1 );
}


sub init_types_base
{
    my( $self, $i ) = @_;

#    warn "***The model of $i is $i->[MODEL]\n";
    croak "Bad interface( $i )" unless ref $i eq "RDF::Service::Resource";

    my $success = 0;

    if( my $entry = $Schema->{$self->[NODE][URISTR]}{NS_RDF.'type'} )
    {
	$self->declare_add_types( &_obj_list($self, $i, $entry),
				  NS_LS.'The_Base_Model', 1 );
	$success = 1;
    }
#    if( my $entry = $Schema->{$self->[NODE][URISTR]}{NS_LS.'name'} )
#    {
#	$self->[NODE][NAME] = $entry;
#    }

    return( $success, 3);
}

sub init_rev_subjs
{
    my( $self, $i, $wanted) = @_;

    return(1,3) if $self->[NODE][REV_SUBJ_I]{$i->[ID]}{'ALL'};

    debug "Reading arcs from base Schema\n", 2;

    my $subj_uri = $self->[NODE][URISTR];
    my $subj = $self;
    $wanted ||= [];

    my $getting_all = 0;
    unless( @$wanted )
    {
	@$wanted = map $self->get_node($_), keys %{$Schema->{$subj_uri}};
	$getting_all = 1;
    }


    foreach my $pred_node ( @$wanted )
    {
	# Check is we already has initialized this pred
	#
	next if $self->[NODE][REV_SUBJ_I]{$i->[ID]}{$pred_node->[ID]};

	# This interface has now initialized this pred.  (Or rather,
	# it *will* do so now.  We set the flag now in order to avoid
	# cycle in _arcs_branch.)
	#
	$self->[NODE][REV_SUBJ_I]{$i->[ID]}{$pred_node->[ID]} = 1;


	my $pred_uri = $pred_node->[URISTR];

	# Make an exception for type
	#
	next if $pred_uri eq NS_RDF.'type';

	my $lref = $Schema->{$subj_uri}{$pred_uri};
	next unless defined $lref;

	# Just define the arcs.
	#
	_arcs_branch($self, $i, $subj, $self->new($pred_node), $lref);

    }

    if( $getting_all )
    {
	$self->[NODE][REV_SUBJ_I]{$i->[ID]}{'ALL'} = 1;
    }

    return(1, 3);
}


sub reset_subClassOf
{
    my( $self, $i, $subClassOf, $wanted  ) = @_;
    #
    # A class inherits it's super-class subClassOf properties

    debug "RDFS init_rev_subjs_class $self->[NODE][URISTR]\n", 1;

    # Old comment, before change to dynamic prop:
    #
    # Since init_rev_subjs_class() depends on that all the other
    # init_rev_subjs has been called, it will call init_rev_subjs()
    # from here.  That would cause an infinite recurse unless the
    # dispatcher would remember which interface subroutines it has
    # called, by storing that in a hash in the context.  The
    # dispatcher will not call the same interface subroutine twice (in
    # deapth) with the same arguments.


    my $node = $self->[NODE];

    # NOTE: Same type of check as in type_orderd_list()
    #
    # We can't use subClassOf for resources used to init subClassOf
    #
    # TODO: Turn off this simplification in RUNLEVEL 2 or somesuch
    #
    if( $node->[URISTR] =~ /^(@{[NS_RDF]}|@{[NS_RDFS]}|@{[NS_LS]})/o )
    {
	return( 3 );
    }


    my @res;

    # Is $self subClassOf any superclass?
    if( $node->[REV_SUBJ]{$subClassOf->[NODE][ID]} )
    {
	# For each superclass
	foreach my $sc ( @{ $self->arc_obj($subClassOf, 1)->list } )
	{
	    push @res, @{ $sc->arc_obj($subClassOf)->list };
	}

	# TODO: Set create dependency on the subject and remove
	# dependency on each added statement and change dependency on
	# object literlas.
    }

    if( $DEBUG >= 2 )
    {
	debug "Returning list of dynamic subClassOf:\n";
	foreach my $obj ( @res )
	{
	    debug "  $obj->[NODE][URISTR]\n";
	}
    }

    # TODO: Add dependent sources to the dynamic model
    my $model = $self->get_dynamic_model( [$i] )->[NODE];
    $self->set_props({$subClassOf->[NODE][URISTR] => \@res}, 1, 1, $model, 1 );

    return( 3 );
}


sub reset_level
{
    my( $self, $i, $level, $wanted ) = @_;

    # The level of a node is a measure of it's place in the class
    # heiarchy.  The Resouce class is level 0.  The level of a class
    # is the level of the heighest superclass plus one.  Used for
    # sorting in type_orderd_list().

    my $node = $self->[NODE];

    # NOTE: Same type of check as in type_orderd_list()
    #
    # We can't calculate level for resources used to calculate level
    #
    if( $node->[URISTR] =~ /^(@{[NS_RDF]}|@{[NS_RDFS]}|@{[NS_LS]})/o )
    {
	return( 1 ); # level already initialized
    }


    my $level_str = 0;
    foreach my $sc ( @{$self->arc_obj_list(NS_RDFS.'subClassOf')} )
    {
	my $sc_level = $sc->arc_obj_value($level);
	defined $sc_level or die "$sc->[NODE][URISTR] should have a level";
	$level_str = $sc_level if $sc_level > $level_str;
    }
    $level_str ++;


    # TODO:
    # Registrer a dependency for this value on
    # $self->arc(NS_RDFS.'subClassOf')

    # TODO: Add dependent sources to the dynamic model
    my $model = $self->get_dynamic_model( [$i] )->[NODE];
    $self->set_props({$level->[NODE][URISTR] => \$level_str}, 1, 1, $model, 1 );
    return( 1 );
}

sub delete_node
{
    my( $self ) = @_;

    # Only deletes the part of the node associated with the WMODEL

    if( $DEBUG )
    {
	unless( ref $self eq 'RDF::Service::Context' )
	{
	    confess "Self $self not Context";
	}
    }

    my $node = $self->[NODE];
    my $wmodel = $self->[WMODEL];
    my $wmodel_id = $wmodel->[NODE][ID];


    die "Not implemented" if $node->[MULTI];

    $self->declare_del_types;
    $self->declare_del_rev_types;

    $node->[REV_PRED_ALL] == 2 or $self->init_rev_preds;
    for(my $j=0; $j<= $#{$node->[REV_PRED]}; $j++)
    {
	# This model does not longer define the arc.  Remove the
	# property unless another model also defines the arc. (In
	# which case delete_node returns false.)

	my $arc_node = $node->[REV_PRED][$j];
	splice @{$node->[REV_PRED]}, $j--, 1
	  if $self->new($arc_node)->delete_node;
    }

    $node->[REV_SUBJ_ALL] == 2 or $self->init_rev_subjs;
    foreach my $subj_id ( keys %{$node->[REV_SUBJ]} )
    {
	for(my $j=0; $j<= $#{$node->[REV_SUBJ]{$subj_id}}; $j++ )
	{
	    # This model does not longer define the arc.  Remove the
	    # property unless another model also defines the arc.

	    my $arc_node = $node->[REV_SUBJ]{$subj_id}[$j];
	    splice @{$node->[REV_SUBJ]{$subj_id}}, $j--, 1
	      if $self->new($arc_node)->delete_node;
	}
	delete $node->[REV_SUBJ]{$subj_id}
	  unless @{$node->[REV_SUBJ]{$subj_id}};
    }

    $node->[REV_OBJ_ALL] == 2 or $self->init_rev_objs;
    foreach my $obj_id ( keys %{$node->[REV_OBJ]} )
    {
	for(my $j=0; $j<= $#{$node->[REV_OBJ]{$obj_id}}; $j++ )
	{
	    # This model does not longer define the arc.  Remove the
	    # property unless another model also defines the arc.

	    my $arc_node = $node->[REV_OBJ]{$obj_id}[$j];
	    splice @{$node->[REV_OBJ]{$obj_id}}, $j--, 1
	      if $self->new($arc_node)->delete_node;
	}
	delete $node->[REV_OBJ]{$obj_id}
	  unless @{$node->[REV_OBJ]{$obj_id}};
    }

    # Should we delete the whole node?
    #
    if( $node->[MULTI] ) # Has another model defined this node?
    {
	# TODO: Something to do here?
	debug "*** Did NOT remove $node->[URISTR]\n";
	debug "***   because of existing model\n";
	die "Not implemented";
    }
    else
    {
	$self->remove;

	# Is this a statement?
	if( $node->[PRED] )
	{
	    debug "Cleaning out the statement node\n", 2;
	    debug "  P $node->[PRED][URISTR]\n", 2;
	    debug "  S $node->[SUBJ][URISTR]\n", 2;
	    debug "  O $node->[OBJ][URISTR]\n", 2;


	    # Filter out this node from connected nodes
	    #
	    # Be careful to actually update the nodes data, and not
	    # only the local values

	    my $rsp = $node->[SUBJ][REV_SUBJ]{$node->[PRED][ID]};
	    @$rsp = grep $_->[ID] != $node->[ID], @$rsp;
	    unless( @$rsp )
	    {
		delete $node->[SUBJ][REV_SUBJ]{$node->[PRED][ID]};
	    }

	    my $rop = $node->[OBJ][REV_OBJ]{$node->[PRED][ID]};
	    @$rop = grep $_->[ID] != $node->[ID], @$rop;
	    unless( @$rop )
	    {
		delete $node->[SUBJ][REV_OBJ]{$node->[PRED][ID]};
	    }

	    my $rp = $node->[PRED][REV_PRED];
	    @$rp = grep $_->[ID] != $node->[ID], @$rp;

	    # Disconnect the node
	    $node->[PRED] = undef;
	    $node->[SUBJ] = undef;
	    $node->[OBJ] = undef;
	}

	delete $node->[MODEL][REV_MODEL]{$node->[ID]};

	# TODO: Is this the right place?
	# $self->changed(['deleted']);

	$node->[MODEL] = undef;
	$self = undef;
    }
    return( 1, 1 );
}

sub delete_node_cascade
{
    my( $self, $i ) = @_;
    #
    # TODO:
    #  1. The agent must be authenticated
    #  2. Is the target model open?
    #  3. Does the agent owns the target model?
    #
    #  Special handling of implicit nodes
    #
    # Delete the node and all statements refering to the node.  How
    # will we handle dangling nodes, like the properties of the node
    # mainly in the form of literals?  We will not delete them if they
    # belong to another model or if they are referenced in another
    # statement (that itself is not among the statements to be
    # deleted).  But there could be references to the node from other
    # interfaces that arn't even connected in this session.
    #
    # We could collect the dangling nodes and return them to the
    # caller for decision.  This could be made to an option.

    # This version will delete from left to right.  A deleted subject
    # will delete all prperty statements and all objects. This will
    # obviously have to change!

    # Procedure:
    #  Foreach statement
    #    - call obj->delete
    #  Remove self

    foreach my $arc ( @{ $self->arc->list} )
    {
	my $obj = $arc->obj;
	$obj->delete_node_cascade();
    }

    return( $self->delete_node, 1 );
}


sub find_node
{
    my( $self, $i, $uri ) = @_;

    my $obj = $RDF::Service::Cache::node->{$self->[NODE][IDS]}{ uri2id($uri) };
    return( $self->new($obj), 1) if $obj;
    return( undef, 0 );
}

sub init_types_service
{
    my( $self, $i ) = @_;
    #
    # We currently doesn't store the service objects in any
    # interface. The Base interface states that all URIs matching a
    # specific pattern are Service objects.

    debug "Initiating types for $self->[NODE][URISTR]\n", 1;

    my $pattern = "^".NS_LD."service/[^/#]+\$";
    if( $self->[NODE][URISTR] =~ m/$pattern/o )
    {
	# Declare the types for the service
	#
	$self->declare_add_types([NS_LS.'Service'], NS_LS.'The_Base_Model', 1);

	return( 0, 3 );
    }

    return 0;
}

sub init_types_literal
{
    my( $self, $i ) = @_;

    debug "Initiating types for $self->[NODE][URISTR]\n", 1;

    my $pattern = "^".NS_LD."literal/[^/#]+\$";
    if( $self->[NODE][URISTR] =~ m/$pattern/o )
    {
	# Declare the types for the literal
	#
	$self->declare_add_types([
	      NS_RDFS.'Literal',
	      ], $self->get_node(NS_LS.'The_Base_Model'), 1);
	return( 0, 3 );
    }
    return 0;
}

sub init_dyn_rev_types
{
    my( $self, $i ) = @_;

    # TODO: The model should be a combination of the interface
    # function and the used sources.

    my $model = $self->get_dynamic_model( [$i] )->[NODE];
    my @rev_types;

    ### Check for DAML+OIL class constraints
    #
    my $unionOf = $self->get( NS_DAML.'unionOf' );
    if( $self->exist_pred( $unionOf ) )
    {
	# TODO: support multipple unionOf and other DAML things
	my $cont = $self->arc_obj($unionOf)->li;
	foreach my $class ( @{$cont->list} )
	{
	    my $class_node = $class->[NODE];

	    # TODO: Check that this is a class

	    $class->init_rev_types unless $class_node->[REV_TYPE_ALL] == 2;

	    # TODO: We don't want to iterate through every REV_TYPE.
	    # We want a functionality similar to container.  A class
	    # should be implemented as a supercalss to container, ie a
	    # collection. (See CyC ontology)

	    foreach my $obj_id ( keys %{$class->[NODE][REV_TYPE]} )
	    {
		push @rev_types, $self->get_context_by_id( $obj_id );
	    }

	    # DEPENDENCY
	    # Changes in unionOf->li contents decides REV_TYPE
	    my $func_uri = "func_uri"; # TODO: Real uri
	    my $func_id = &uri2id( $func_uri );
	    $cont->[NODE][DECIDES]{'selection'}{$self->[NODE][ID]}
	    {'init_dyn_rev_types'}{$func_id} =  [];
	}

	# TODO: Changes in the rev_types for each class decides
	# rev_type for $node
    }

    $self->set_rev_types( \@rev_types, 1, 1, $model );

    return( 0, 3 );
}

sub desig_literal
{
    if( $_[0]->[NODE][VALUE] )
    {
	return( "'${$_[0]->[NODE][VALUE]}'", 1);
    }
    else
    {
	return( "''", 1);
#	return( desig($_[0]) );
    }
}

sub desig_statement
{
    my( $self ) = @_;

    my( $str ) = desig_resource($self);

    my $pred = $self->pred->desig;
    my $subj = $self->subj->desig;
    my $obj  = $self->obj->desig;

    $str .= ": $pred of $subj is $obj\n";
    return( $str, 1);
}

sub desig_resource
{
    my( $self ) = @_;

    my $str = ( $self->arc_obj_value(NS_RDFS.'label') ||
#		$_[0]->[NODE][NAME] ||
		$self->[NODE][URISTR] ||
		'(anonymous resource)'
		);

    return( $str, 1 );
}


sub get_multi_arc
{
    my( $self, $i, $pred_uristr ) = @_;

    my $node = $self->[NODE];

    debug "  ( $pred_uristr )\n";

    # TODO: Handle multipple properties (in diffrent models)
    # TODO: Handle multi arc in deletion process

    # is there an existing arc for this multi?
    if( $node->[MULTI] )
    {
	foreach my $arc_node ( @{$node->[MULTI]} )
	{
	    if( $arc_node->[PRED][URISTR] eq $pred_uristr )
	    {
		debug "Returning existing arc $arc_node->[URISTR]\n";
		return( $self->new($arc_node), 1);
	    }
	}
    }

    # The arc does not yet exist. Create it
    # TODO: Use special model
    my $object;
    if( $pred_uristr eq NS_RDF.'predicate' )
    {
	$object = $node->[PRED];
    }
    elsif( $pred_uristr eq NS_RDF.'subject' )
    {
	$object = $node->[SUBJ];
    }
    elsif( $pred_uristr eq NS_RDF.'object' )
    {
	$object = $node->[OBJ];
    }
    else
    {
	die "not implemented: '$pred_uristr'";
    }
    my $arc = $self->declare_add_prop( $pred_uristr, $object->[URISTR] );

#     my $arc = $self->get->set(
# 	  [NS_RDF.'Statement'],
# 	{
# 	    NS_RDF.'predicate' => $pred_uristr,
# 	    NS_RDF.'subject' => $self,
# 	    NS_RDF.'object' => $self->new($object),
# 	});
#    debug "Arc is $arc\n";
    $arc->[NODE][MULTI] ||= []; # Initialize if this is the first
    push @{$arc->[NODE][MULTI]}, $arc->[NODE];
    debug "Returning new arc $arc->[NODE][URISTR]\n";
    return( $arc, 1);
}

##############################


# All methods with the prefix 'list_' will return a list of objects
# rather than a collection. (Model or collection of resources or
# literals.)  But teh method will still return a ref to the list to
# the Dispatcher.

sub value
{
    my( $self ) = @_;
    $self->[NODE][REV_SUBJ_ALL] == 2 or $self->init_rev_subjs;

#    warn "**** ".($self->types_as_string)."****\n";
    if( not defined $_[0]->[NODE][VALUE] )
    {
	die "$self->[NODE][URISTR] has no defined value\n";
    }

    # TODO: Should return 2
    return( ${$_[0]->[NODE][VALUE]}, 1);
}

##############################
#
# Arcs
#

sub pred
{
    # TODO. Should return 2;
    return( $_[0]->new($_[0]->[NODE][PRED]), 1);
}

sub subj
{
    # TODO. Should return 2;
    return( $_[0]->new($_[0]->[NODE][SUBJ]), 1);
}

sub obj
{
    # TODO. Should return 2;
    return( $_[0]->new($_[0]->[NODE][OBJ]), 1);
}


##############################
#
# Containers
#

sub li
{
    my( $self, $i ) = @_;

    # TODO: Add support for criterions

    my $node = $self->[NODE];

    my $cnt = $self->arc_obj_value(NS_LS.'size');
    if( $cnt == 1 )
    {
	$node->[CONTENT_ALL] or _expand($node);
	return( $self->new($node->[CONTENT][0]), 1);
    }
    else
    {
	die "Selection $node->[URISTR] has $cnt resources, while expecting one\n";
    }
}

sub list
{
    my( $self, $i ) = @_;

    # TODO: Convert the contents to individual objects.  Maby tie the
    # list to a list object for iteration through the list.

    my $node = $self->[NODE];

    if( $DEBUG > 2 )
    {
	my $cnt = $self->arc_obj_value(NS_LS.'size');
	unless( defined $cnt )
	{
	    debug "We expected $node->[URISTR] to be a container\n";
	    debug $self->types_as_string;

	    debug "The DYNTABLE looks like this:\n";
	    foreach my $func ( keys %{$node->[DYNTABLE]} )
	    {
		debug "  $func\n";
	    }
	    confess "The size was undefined";
	}
	debug "Returning a list of $cnt resources\n", 1;
    }

    $node->[CONTENT_ALL] or _expand($node);

    # You should iterate through the nodes if it's a large list.  Now
    # we make another copy of the list. (Apart from SELECT and
    # CONTENT)
    #
    my $list = [];
    foreach my $res ( @{$node->[CONTENT]} )
    {
	push @$list, $self->new( $res );
    }

    return( $list, 1);
}

sub reset_size
{
    my( $self, $i, $size, $wanted ) = @_;

    # TODO: This function is too costly! Optimize!!!

    my $node = $self->[NODE];
    $node->[CONTENT_ALL] or _expand($node);

    my $cnt = @{$node->[CONTENT]};

    # This function is to basic for using set_props.  We will update
    # the value by hand

    my $model_con = $self->get_dynamic_model( [$i] );

    my $arc_node = $node->[REV_SUBJ]{$size->[NODE][ID]}[0];
    my $arc = $self->new($arc_node);

    if( $arc_node )
    {
	unless( $arc_node->[OBJ][VALUE] == $cnt )
	{
	    $self->new( $arc_node )->delete_node;
	    $arc = $model_con->declare_arc( $size, $self, \$cnt, undef, undef, 1);
	}
    }
    else
    {
	$arc = $model_con->declare_arc( $size, $self, \$cnt, undef, undef, 1);
    }

    # DEPENDENCY
    my $func_uri = "func_uri"; # TODO: Real uri
    my $func_id = &uri2id( $func_uri );
    $node->[DECIDES]{'selection'}{$node->[ID]}
    {'init_rev_subjs'}{$func_id} =  [$size]; # default = all

    return( 1 );
}

sub _expand
{
    my( $node ) = @_;

    # Todo Go through the selection entries.  Should realy only expand
    # the needed part.  Not everything at once.

    # For now, just copy them
    $node->[CONTENT] = [];
    foreach my $entry ( @{$node->[SELECTION]} )
    {
	push @{$node->[CONTENT]}, $entry;
    }
    $node->[CONTENT_ALL] = 1;
}

sub sel  # select
{
    my( $self, $i, $point ) = @_;

    # Now, how should we go about this?  The $self is a container.
    # The content can partly be another selection.  We will iterate
    # through the container.  If the parts is a selection or antother
    # group, a new selection will be created by joining the
    # constraints.  Those parts will be expanded then needed, then
    # li() or size() is called.  li() should only expand the needed
    # part.  Specifically, it should support iteration through the
    # selection.

    unless( ref $point eq 'HASH' )
    {
	die "Not implemented";
    }

    my $node = $self->[NODE];

    my $content = [];
    my $cnt = @{$node->[SELECTION]};
    debug "..The container has $cnt entries\n", 2;
    foreach my $entry ( @{$node->[SELECTION]} )
    {
	if( ref $entry eq "RDF::Service::Resource" )
	{
	    # TODO: Could we defere this to later?
	    if( _test( $self, $entry, $point ) )
	    {
		push @$content, $entry;
	    }
	}
	else
	{
	    die "Not implemented";
	    # TODO: Merge the $point with the previous
	}
    }

    my $selection = $self->declare_selection( $content );
    return( $selection, 1 );
}

sub _test
{
    my( $self, $entry, $point ) = @_;

    # TODO: Use the context. (But maby not here)

    debug "....checking $entry->[URISTR]\n", 2;

    if( ref $point eq 'HASH' )
    {
	return 0 unless _test_hash( $self, $entry, $point );
    }
    else
    {
	die "Not implemented";
    }
    debug "....PASSED!\n", 2;
    return 1;
}

sub _test_hash
{
    my( $self, $entry, $point ) = @_;

    $entry->[REV_SUBJ_ALL] == 2 or $self->new( $entry )->init_rev_subjs;

    foreach my $pred_key ( keys %$point )
    {
	my  $pred_uristr = $pred_key;
	debug "......Pred $pred_uristr\n", 2;

	my $arcs = undef;

	# Checks for abbrevations
	if( my $x = $self->[SESSION][ABBREV]{$pred_uristr} )
	{
	    debug "......abbrev for $x->[NODE][URISTR]\n", 2;
	    $pred_uristr = $x->[NODE][URISTR];
	}

	# Checks for special properties
	if( $pred_uristr =~ /^@{[NS_RDF]}(predicate|subject|object)$/o )
	{
	    # The solution is to expand special properties to explicit
	    # arcs.

	    # TODO; Handle MULTI nodes
#	    warn "*** pred_uristr: $pred_uristr\n";
	    $arcs = [$self->new($entry)->get_multi_arc($pred_uristr)->[NODE]];
	}

	# Default, if not a special property
	$arcs ||= $entry->[REV_SUBJ]{uri2id($pred_uristr)};


	unless( $arcs )
	{
	    debug "......Non found\n", 2;
	    return 0;
	}

	debug "......Has ".scalar(@$arcs)." objs\n", 2;

	my $crit = $point->{$pred_key};

	unless( ref $crit eq 'ARRAY' )
	{
	    $crit = [$crit];
	}

#	$Data::Dumper::Maxdepth = 3; ## DEBUG
#	warn Dumper( $crit );

	return 0 unless _test_array( $self, $arcs, $crit );
    }
    debug "......PASSED!\n", 2;
    return 1;
}

sub _test_array
{
    my( $self, $arcs, $point ) = @_;

    foreach my $arc ( @$arcs )
    {
	my $obj = $arc->[OBJ];

#	debug "Arc is $arc\n"; ###
	debug "........Obj $obj->[URISTR]\n", 2;

	foreach my $alt ( @$point )
	{
	    if( ref $alt eq 'SCALAR' )
	    {
		return 1 if _test_scalar( $self, $obj, $alt );
		next; # Was 'return 0;'
	    }
	    elsif( ref $alt eq 'HASH' )
	    {
		return 1 if _test_hash( $self, $obj, $alt );
		next;
	    }
	    elsif( not defined $alt )
	    {
		confess "Alt undefined";
	    }
	    elsif( not ref $alt )
	    {
#		debug "Alt is $alt";
		$alt = $self->get_abbrev( $alt );
	    }

#	    debug "??? $$alt\n"; ### DEBUG
	    debug "..........Is $obj->[URISTR] eq $alt->[NODE][URISTR] ?\n",2;
	    if( $obj->[ID] == $alt->[NODE][ID] )
	    {
		debug "..........YES!\n", 2;
		return 1;
	    }
	    else
	    {
		debug "..........NO\n", 2;
	    }
	}
    }
    debug "........FAILED!\n", 2;
    return 0;
}

sub _test_scalar
{
    my( $self, $obj, $point ) = @_;

    unless( $self->new( $obj )->is_a( NS_RDFS.'Literal' ) )
    {
	die "Object $obj->[URISTR] is not a literal";
    }

    debug "..........Is ${$obj->[VALUE]} eq $$point ?\n",2;

    if( ${$obj->[VALUE]} eq $$point )
    {
	debug "..........YES!\n", 2;
	return 1;
    }
    else
    {
	debug "..........NO\n", 2;
	return 0;
    }
}

##############################
#
# Helper functions
#
sub _export_to_ids
{
    my( $self, $i, $node, $new_ids ) = @_;

    debug_start( "_export_to_ids", ' ', $self );

#    warn "BBB1 Start by exporting $node->[URISTR]\n";

    _export_to_ids_node( $self, $i, $node, $new_ids );
#    warn "BBB2\n";

    foreach my $id ( keys %{$node->[REV_MODEL]} )
    {
#    warn "BBB3\n";
	my $sub = $self->get_context_by_id($id);
	if( $sub->is_known_as_a( NS_LS.'Model' ) )
	{
#    warn "BBB4\n";
	    next if $sub->[NODE][ID] == $node->[ID];
	    debug "Is a model ($sub->[NODE][URISTR]), ".
	      "checking it's content\n", 2;
	    _export_to_ids( $self, $i, $sub->[NODE], $new_ids );
	}
	else
	{
#    warn "BBB5\n";
	    next if $sub->[NODE][SOLID];
	    _export_to_ids_node( $self, $i, $sub->[NODE], $new_ids );
	}
    }
 #   warn "BBB6\n";

    # Transferens done. Empty list:
    #
    my $m = $self->[MEMORY]{$i->[ID]} ||= {};
    $m->{'transfered'} = undef;

    debug_end( "_export_to_ids", ' ', $self );
}

sub _export_to_ids_node
{
    my( $self, $i, $subnode, $new_ids ) = @_;

    unless( $i->[ID] )
    {
	confess "Invalid interface ( $i )";
    }

    my $cache = $RDF::Service::Cache::node->{$new_ids};

    # Do not export the node if it's already exist in the new_ids.
    # TODO:  Do another export to *update* the new node
    return if $cache->{$subnode->[ID]};


    # Remember which nodes we have transfered
    #
    my $m = $self->[MEMORY]{$i->[ID]} ||= {};
    return if $m->{'transfered'}{$subnode->[ID]};
    $m->{'transfered'}{$subnode->[ID]} ++;



    debug_start("_export_to_ids_node", ' ', $self );
    debug "  Exporting $subnode->[URISTR] $subnode->[ID] ".
      "(IDS $subnode->[IDS])\n", 3;

    if( $DEBUG )
    {
	my $donelist = [sort keys %{$m->{'transfered'}}];
	debug "MEMORY @$donelist\n";
    }


    my $new_node = $self->get_node_by_id($subnode->[ID], $new_ids);


    # The $new_node has responsability now
    #
    debug "Changing SOLID to $subnode->[SOLID] for $new_node->[URISTR] ".
      "IDS $new_node->[IDS]\n", 3;
    $new_node->[SOLID] = $subnode->[SOLID];
    debug "Changing SOLID to 1 for $subnode->[URISTR] ".
      "IDS $subnode->[IDS]\n", 3;
    $subnode->[SOLID] = 1;

    my $model_id = $self->[WMODEL][NODE][ID];
#    warn "AAA1\n";

    $new_node->[IDS] = $new_ids;
    $new_node->[MEMBER] = $subnode->[MEMBER];
    $new_node->[MULTI] = $subnode->[MULTI];
    $new_node->[VALUE] = $subnode->[VALUE];
    $new_node->[LANG] = $subnode->[LANG];

    # TODO: Transfer CONTENT (and READONLY)
    # TODO: Transfer PREFIX, MODULE_NAME, MODULE_REG and INTERFACES



    # Get the model from the new IDS
    if( $subnode->[MODEL] )
    {
	_export_to_ids_node( $self, $i, $subnode->[MODEL], $new_ids );
	my $subnode_model =
	  $self->get_node_by_id( $subnode->[MODEL][ID], $new_ids );
	debug "subnode_model  $subnode_model->[URISTR] ".
	  "IDS  $subnode_model->[IDS]\n", 3;
	$new_node->[MODEL] = $subnode_model;
	$new_node->[MODEL][REV_MODEL]{$new_node->[ID]} = $new_node;
    }

#	$new_node->[ALIASFOR] = $subnode->[ALIASFOR];

	my $new = $self->new($new_node);


#    warn "AAA2\n";

    foreach my $type_id ( keys %{$subnode->[TYPE]} )
    {
	my $old_type_node = $self->get_node_by_id( $type_id );
	debug "  TYPE $old_type_node->[URISTR] IDS $new_ids\n", 4;
	debug "    Checking...\n", 4;

	next unless $subnode->[TYPE]{$type_id};
	if( $DEBUG >= 4 )
	{
	    next unless $subnode->[TYPE]{$type_id}{$model_id};
	    debug "    Solidity is ".
	      $subnode->[TYPE]{$type_id}{$model_id} ."\n", 2;
	}

	# Only transfer types belonging to the working model, that
	# are marked as NONSOLID (==1)
	#
	unless( $subnode->[TYPE]{$type_id}{$model_id} and
		  $subnode->[TYPE]{$type_id}{$model_id} == 1 )
	{
	    next;
	}

	_export_to_ids_node( $self, $i, $old_type_node, $new_ids );
	my $type_node = $new->get_node_by_id( $type_id, $new_ids );

	debug "    Transfering!\n", 4;

	$subnode->[TYPE]{$type_id}{$model_id} = 2;
	$new_node->[TYPE]{$type_id}{$model_id} = 1;

	$type_node->[REV_TYPE]{$new_node->[ID]}{$model_id} = 1;

	if( $DEBUG )
	{
	    my $model_uri = id2uri( $model_id );
	    debug "Setting $type_node->[URISTR] ".
	      "(IDS $type_node->[IDS]) ".
		"REV_TYPE $new_node->[URISTR] ".
		  "(IDS $new_node->[IDS]) ".
		    "in model $model_uri\n";
	}
    }

    # NB: REV_TYPE is ignored

#    warn "AAA3\n";

    foreach my $arc_node ( @{$subnode->[REV_PRED]} )
    {
	next unless $arc_node->[MODEL];
	next unless $arc_node->[MODEL][ID] == $model_id;
	next if $arc_node->[SOLID];
	debug "  REV_PRED $arc_node->[URISTR]\n", 2;
	_export_to_ids_node( $self, $i, $arc_node, $new_ids );
	my $new_arc_node =
	  $self->get_node_by_id( $arc_node->[ID], $new_ids );
	push @{$new_node->[REV_PRED]}, $new_arc_node;
    }

#    warn "AAA4\n";

    foreach my $pred_id ( keys %{$subnode->[REV_SUBJ]} )
    {
	$new_node->[REV_SUBJ]{$pred_id} = [];
	foreach my $arc_node ( @{$subnode->[REV_SUBJ]{$pred_id}} )
	{
	    next unless $arc_node->[MODEL];
	    next unless $arc_node->[MODEL][ID] == $model_id;
	    next if $arc_node->[SOLID];
	    debug "  REV_SUBJ $arc_node->[URISTR]\n", 2;
	    _export_to_ids_node( $self, $i, $arc_node, $new_ids );
	    my $new_arc_node =
	      $self->get_node_by_id( $arc_node->[ID], $new_ids );
	    push @{$new_node->[REV_SUBJ]{$pred_id}}, $new_arc_node;
	}
	delete $new_node->[REV_SUBJ]{$pred_id} unless
	  @{$new_node->[REV_SUBJ]{$pred_id}};
    }

#    warn "AAA5\n";

    foreach my $pred_id ( keys %{$subnode->[REV_OBJ]} )
    {
	$new_node->[REV_OBJ]{$pred_id} = [];
	foreach my $arc_node ( @{$subnode->[REV_OBJ]{$pred_id}} )
	{
	    next unless $arc_node->[MODEL];
	    next unless $arc_node->[MODEL][ID] == $model_id;
	    next if $arc_node->[SOLID];
	    debug "  REV_OBJ $arc_node->[URISTR]\n", 2;
	    _export_to_ids_node( $self, $i, $arc_node, $new_ids );
	    my $new_arc_node =
	      $self->get_node_by_id( $arc_node->[ID], $new_ids );
	    push @{$new_node->[REV_OBJ]{$pred_id}}, $new_arc_node;
	}
	delete $new_node->[REV_OBJ]{$pred_id} unless
	  @{$new_node->[REV_OBJ]{$pred_id}};
    }

#    warn "AAA6\n";

    if( $subnode->[PRED] )
    {
	debug "  PRED/SUBJ/OBJ\n", 2;


	_export_to_ids_node( $self, $i, $subnode->[PRED], $new_ids );
	my $new_pred_node =
	  $self->get_node_by_id($subnode->[PRED][ID], $new_ids);
	push @{$new_pred_node->[REV_PRED]}, $new_node;
	$new_node->[PRED] = $new_pred_node;

	my $pred_id =  $new_node->[PRED][ID];

	_export_to_ids_node( $self, $i, $subnode->[SUBJ], $new_ids );
	my $new_subj_node =
	  $self->get_node_by_id($subnode->[SUBJ][ID], $new_ids);
	push @{$new_subj_node->[REV_SUBJ]{$pred_id}}, $new_node;
	$new_node->[SUBJ] = $new_subj_node;

	_export_to_ids_node( $self, $i, $subnode->[OBJ], $new_ids );
	my $new_obj_node =
	  $self->get_node_by_id($subnode->[OBJ][ID], $new_ids);
	push @{$new_obj_node->[REV_OBJ]{$pred_id}}, $new_node;
	$new_node->[OBJ] = $new_obj_node;
    }


#    warn "AAA7\n";

    $cache->{$new_node->[ID]} = $new_node;

    debug_end( "_export_to_ids_node", ' ', $self );
}

sub _construct_interface_uri
{
    my( $module, $args ) = @_;

    # Generate the URI of interface object. This will have to
    # change. The URI should be known or availible by request. Not
    # guessed.  Make a clear distinction between the interface module
    # resource and the interface resource returned from a connection.
    #
    my $uri = URI->new("http://cpan.org/rdf/module/"
		       . join('/',split /::/, $module));

    if( ref $args eq 'HASH' )
    {
	my @query = ();
	foreach my $key ( sort keys %$args )
	{
	    next if $key eq 'passwd';
	    push @query, $key, $args->{$key};
	}
	$uri->query_form(@query);
    }
    return $uri->as_string;
}


sub _obj_list
{
    my( $self, $i, $ref ) = @_;
    my @objs = ();

    if( ref $ref eq 'SCALAR' )
    {
	push @objs, $self->get($$ref);
    }
    elsif( ref $ref eq 'ARRAY' )
    {
	foreach my $obj ( @$ref )
	{
	    push @objs, _obj_list( $self, $i, $obj );
	}
    }
    else
    {
	push @objs, $self->declare_literal($i, undef, $ref);
    }

    return \@objs;
}

sub _arcs_branch
{
    my( $self, $i, $subj, $pred, $lref ) = @_;

    my $arcs = [];
    my $obj;
    if( ref $lref and ref $lref eq 'SCALAR' )
    {
	my $obj_uri = $$lref;
	$obj = $self->get($obj_uri);
    }
    elsif( ref $lref and ref $lref eq 'HASH' )
    {
	# Anonymous resource
	# (Sublevels is not returned)

	die "Anonymous resources not supported";
#	$obj = RDF::Service::Resource->new($ids, undef);
    }
    elsif(  ref $lref and ref $lref eq 'ARRAY' )
    {
	foreach my $item ( @$lref )
	{
	    _arcs_branch($self, $i, $subj, $pred, $item);
	}
	return 1;
    }
    else
    {
	confess("_arcs_branch called with undef obj: ".Dumper(\@_))
	    unless defined $lref;

	# TODO: The model of the statement should be NS_RDFS or NS_RDF
	# or NS_LS, rather than $i
	#
	debug "_arcs_branch adds literal $lref\n", 1;
	$obj = $self->declare_literal( \$lref );
    }

    # TODO: Handle name

    unless( $pred->[NODE][URISTR] eq NS_RDF.'type' or
	  $pred->[NODE][URISTR] eq NS_LS.'name' )
    {
	$self->declare_arc( $pred, $subj, $obj, undef,
			    undef, 1 );
    }
    return 1;
}


1;
