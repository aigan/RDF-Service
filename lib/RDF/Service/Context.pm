#  $Id: Context.pm,v 1.32 2001/04/11 16:51:20 aigan Exp $  -*-perl-*-

package RDF::Service::Context;

#=====================================================================
#
# DESCRIPTION
#   All resources exists in a context. This is the context.
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
use vars qw( $AUTOLOAD );
use RDF::Service::Dispatcher qw( go create_jumptable select_jumptable
				 %JumpJumpTable %JumpPropTable );
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( interfaces uri2id list_prefixes
			    get_unique_id id2uri debug
			    debug_start debug_end
			    $DEBUG expire time_string $Level
			    validate_context $dynamic_model);
use Data::Dumper;
use Carp qw( confess cluck croak);

sub new
{
    my( $proto, $node, $context, $wmodel, $session ) = @_;

    # This constructor shouls only be called from get(), which
    # could be called from find_node or create_node.

    my $class = ref($proto) || $proto;
    my $self = bless [], $class;

    my $history = [];

    if( ref($proto) )
    {
	$context ||= $proto->[CONTEXT];
	$node    ||= $proto->[NODE]; # The same node in another context?
	$wmodel  ||= $proto->[WMODEL];
	$session ||= $proto->[SESSION];

	$history = $proto->[HISTORY];
    }

    unless( ref($history) eq 'ARRAY' )
    {
	confess "HOLY SHIT!!!";
    }

    # TODO: Maby perform a deep copy of the context.  At least copy
    # each key-value pair.

    $self->[NODE]    = $node or die;
    $self->[CONTEXT] = $context or die "No context supplied";
    $self->[WMODEL]  = $wmodel;
    $self->[SESSION] = $session;
    $self->[MEMORY]  = {};
    $self->[HISTORY] = $history;

#    debug "  Session is $session\n", 2;

    if( $node->[RUNLEVEL] )
    {
	$wmodel or confess "No WMODEL supplied by $proto\n";
	$session or confess "No session supplied by $proto\n";

	unless( ref $session eq "RDF::Service::Resource" )
	{
	    confess "Holy shit: $session!!!";
	}
    }

    return $self;
}


sub AUTOLOAD
{
    # The substr depends on the package length
    #
    $AUTOLOAD = substr($AUTOLOAD, 23);
    return if $AUTOLOAD eq 'DESTROY';
    debug "AUTOLOAD $AUTOLOAD\n", 2;

#    warn "*** Level = $Level\n"; ### DEBUG
#    warn "*** DEBUG = $DEBUG\n\n";

    # Expand abbrevations only for the app
    if( $Level == 0 )
    {
	my $self = shift;

	debug "  Checking for abbrevation\n", 2;
#	debug "  Self is $self->[NODE][URISTR]\n", 2;
#	debug "  Session is $self->[SESSION][URISTR]\n", 2;
#	debug "Abbrevations:\n".Dumper($self->[SESSION][ABBREV])."\n", 2;

	if( substr($AUTOLOAD, 0, 4) eq 'rev_')
	{
	    if( my $x = $self->[SESSION][ABBREV]{substr($AUTOLOAD, 4)} )
	    {
		return $self->arc_subj($x, @_);
	    }
	    else
	    {
		debug "  Non found for ".substr($AUTOLOAD, 4)."\n", 2;
		return &RDF::Service::Dispatcher::go($self, $AUTOLOAD, @_);
	    }
	}
	else
	{
	    if( my $x = $self->[SESSION][ABBREV]{$AUTOLOAD} )
	    {
		return $self->arc_obj($x, @_);
	    }
	    else
	    {
		debug "  Non found for $AUTOLOAD\n", 2;
		return &RDF::Service::Dispatcher::go($self, $AUTOLOAD, @_);
	    }
	}
    }

    return &RDF::Service::Dispatcher::go(shift, $AUTOLOAD, @_);
}


#sub name
#{
#    my( $self ) = @_;
#    return $self->[NODE][NAME]; # not guaranteed to be defined
#}

sub uri
{
    # This is always defined
    $_[0]->[NODE][URISTR];
}

sub model
{
    my( $self ) = @_;
    die "not implemented" if $_[0]->[NODE][MULTI];

    my $model_res = $_[0]->new( $_[0]->[NODE][MODEL] );

    if( $DEBUG )
    {
	unless( $model_res->is_a( NS_LS.'Model' ) )
	{
	    die "The model is not a model";
	}
    }

    return $model_res;

    # TODO: Should return a selection of models
}

sub get_abbrev
{
    if( my $res = $_[0]->[SESSION][ABBREV]{$_[1]} )
    {
	return $res;
    }

    # The rest is the same as get()
    unless( $_[1] )
    {
	return get_context_by_id( $_[0],
				  uri2id(NS_LD.&get_unique_id),
				  $_[2], 1 );
    }
    return get_context_by_id( $_[0], uri2id($_[1]), $_[2] );
}

sub get
{
    unless( $_[1] )
    {
	return get_context_by_id( $_[0],
				  uri2id(NS_LD.&get_unique_id),
				  $_[2], 1 );
    }
    return get_context_by_id( $_[0], uri2id($_[1]), $_[2] );
}

sub get_context_by_id
{
    my( $self, $id , $ids, $local ) = @_;
    #
    # $local guarantees that no info about the resource exists in the
    # interfaces.  Only fetch dynamic properties.


    # TODO: First look for the object in the cache

    my $node = $self->[NODE];
    $ids ||= $node->[IDS];
    $local ||= 0;

    if( $DEBUG )
    {
	confess "IDS undefined" unless defined $ids;
	unless( ref $RDF::Service::Cache::node->{$ids} )
	{
	    $node->[RUNLEVEL] and
	      confess "IDS $ids not initialized\n";
	}

	confess "id not defined" unless $id;
    }

    my $obj = $RDF::Service::Cache::node->{$ids}{ $id };

    unless( $obj )
    {
	# Create an uninitialized object. Any request for the objects
	# properties will initialize the object with the interfaces.

	$obj = $node->new_by_id($id);

	$RDF::Service::Cache::node->{$ids}{ $id } = $obj;
    }

    $obj->[LOCAL] = $local;


    if( $DEBUG )
    {
	unless( $self->[WMODEL] or
		  $obj->[URISTR] eq NS_LS.'The_Base_Model' )
	{
	    confess "No WMODEL found for $node->[URISTR] ";
	}

	unless( ref $obj eq "RDF::Service::Resource" )
	{
	    my $uri = id2uri( $id );
	    confess "Cached $uri ($id) corrupt";
	}
    }

    return $self->new( $obj );
}


sub get_node
{
    unless( $_[1] )
    {
	return get_node_by_id( $_[0],
			       uri2id(NS_LD.&get_unique_id),
			       $_[2], 1 );
    }
    return get_node_by_id( $_[0], uri2id($_[1]), $_[2] );
}

sub get_node_by_id
{
    my( $self, $id, $ids, $local ) = @_;

    $ids ||= $self->[NODE][IDS];
    $local ||= 0;

    my $obj = $RDF::Service::Cache::node->{$ids}{ $id };

    unless( $obj )
    {
	# Create an uninitialized object. Any request for the objects
	# properties will initialize the object with the interfaces.

	$obj = $self->[NODE]->new(undef, $id, $ids);

	$RDF::Service::Cache::node->{$ids}{ $id } = $obj;
    }

    $obj->[LOCAL] = $local;


    if( $DEBUG )
    {
	unless( $self->[WMODEL] or
		  $obj->[URISTR] eq NS_LS.'The_Base_Model' )
	{
	    confess "No WMODEL found for $self->[NODE][URISTR] ";
	}

	unless( ref $obj eq "RDF::Service::Resource" )
	{
	    my $uri = id2uri( $id );
	    confess "Cached $uri ($id) corrupt";
	}
    }

    return $obj;
}

sub get_dynamic_model
{
    my( $self, $parts ) = @_;

    debug_start("get_dynamic_model", ' ', $self);

    # TODO: This raised for me the question of what the model for the
    # dynamic properties should be.  Who is stating the statement?
    # It's a combination of:
    #
    #   - The model of the program code
    #   - The model of all data used as input
    #
    # My previous thought, if I remember, was to create a custom model
    # for the specific combination, and put the data about the
    # involved models as metadata for that model.
    #
    # I think that the agent property of the model will be used as a
    # base for trust.  For dynamic properties, a group could be used
    # as agent.  The first time the group is encounterd, we could
    # check each agent.  But then we could trust the group.  That
    # would mean that the agent would be a bag of agents.
    #
    # Should every dynamic property be placed in a unique model?  Or
    # should we group properties that has identical metadata, maby
    # within the same session?  But the session doesn't have a clear
    # connection to the dynamic properties, other than maby as the
    # model for a part of the source data.  Ah, thats it!  A new
    # session results in a new source model and a new dynamic model.

    # TODO: The dynamic model should include a bag of agents.  Sort
    # the parts.  Look up the model in a optimized search for a model
    # having these parts.  If non exist, create the model and
    # set its types and properties.  If the model do exist, return it.

    # TODO: $dyn_model->[NODE][MODEL] should be The_Base_Model

    my $key = join '-', sort {$a->[NODE][ID] <=> $b->[NODE][ID]} @$parts;

    my $model = $dynamic_model->{$key};

    unless( $model )
    {
	$model = $self->get(NS_LD."dynamic_model/".&get_unique_id);
	$dynamic_model->{$key} = $model;
	$self->create_model($model);
    }

    debug_end("get_dynamic_model", ' ', $self);

    return $model;
};



sub get_model
{
    my( $self, $uri ) = @_;

    debug_start("get_model", ' ', $self);

# Does not work. Must include creation time
# Not short for get->set([NS_LS.'Model'])
#    $self->get($uri)->set([NS_LS.'Model']);

    die "No uri specified" unless $uri;
    debug "  ( $uri )\n", 2;

    my $obj = $self->find_node( $uri );
    if( $obj )
    {
	debug "Model existing: $uri\n", 1;
	# Is this a model?
	unless( $obj->is_a(NS_LS.'Model') )
	{
	    die "$obj->[NODE][URISTR] is not a model\n".
	      $obj->types_as_string;
	}
	# setting WMODEL
	$obj->[WMODEL] = $obj;
    }
    else
    {
	debug "Model not existing. Creating it: $uri\n", 1;
	# create_model sets WMODEL
	$obj = $self->create_model( $uri );
    }

    debug_end("get_model", ' ', $self);
    return $obj;
}


sub create_model
{
    my( $self, $obj, $content ) = @_;

    # NOTE: Moved from Base, because this function is needed during
    # the session model initialization

    ### NOTES from old create_model in DBI
    #
    # We are asked to create a new resource and a new object
    # representing that resource and a context for the resource
    # object.  The new resource must have an URI.  The creator must
    # own the $uri namespace, as statements will be placed in it..

    # If no URI is supplied, one will be generated by the method
    # create_resource().  In case the URI is supplied, it will
    # be validated by the appropriate interface.


    # TODO: Validate the URI


    debug_start("create_model", ' ', $self);

    $content ||= [];
    my $local = 0;

    unless( ref $obj )
    {
	unless( defined $obj )
	{
	    $obj = NS_LD."model/".&get_unique_id;
	    $local = 1;
	}
	$obj = $self->get( $obj );
    }

    my $obj_node = $obj->[NODE];
    debug "  ( $obj_node->[URISTR] )\n", 2;



    # The model consists of triples. The [content] holds the access
    # points for the parts of the model. Each element can be either a
    # triple, model, ns, prefix or interface. Each of ns, prefix and
    # interface represents all the triples contained theirin.

    # the second parameter is the interface of the created object
    # That parameter will be removed and the interface list will be
    # created from the availible interfaces as pointed to by the
    # context signature.


    $obj_node->[MODEL] = $self->[WMODEL][NODE];
    $self->[WMODEL][NODE][REV_MODEL]{$obj_node->[ID]} = $obj_node;
#    $obj_node->[NS]       = $obj_node->[URISTR];
    $obj_node->[SELECTION]  = $content;
    $obj_node->[READONLY] = 0;
    $obj_node->[LOCAL] = $local;


    # The working model of the model will be the model itself.  But
    # the model of the model will be the working model of it's parent.

    # What is the model of the model?  Is it the parent model
    # ($self->[MODEL]) or itself ($model) or some default
    # (NS_LD."model/system") or maby the interface?  Answer: Its the
    # parent model.  Commonly the Service object.
    #
    $obj->[WMODEL] = $obj;

    my $types = [ NS_LS.'Model' ];
    my $props =
    {
	NS_LS.'updated' => [ \ time_string()],
    };

    # Should the WMODEL not be $obj while we are setting the type of
    # obj?
    #
    $obj->set( $types, $props );

    debug_end("create_model", ' ', $self);

    return $obj;
}

sub is_a
{
    my( $self, $class ) = @_;

    $self->[NODE][TYPE_ALL] == 2 or $self->init_types;
    return $self->is_known_as_a( $class );
}

sub could_be_a
{
    my( $self, $class ) = @_;

    return 1 unless $self->[NODE][TYPE_ALL] == 2;
    return $self->is_known_as_a( $class );
}

sub is_known_as_a
{
    my( $self, $class ) = @_;

    $class = $self->get( $class ) unless ref $class;

    if( defined $self->[NODE][TYPE]{$class->[NODE][ID]} )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub exist_pred
{
    my( $self, $pred ) = @_;

    my $pred_id;
    if( ref $pred )
    {
	$pred_id = $pred->[NODE][ID];
    }
    else
    {
	$pred_id = uri2id( $pred );
    }

    if( $self->[NODE][REV_SUBJ]{$pred_id} )
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub type_orderd_list
{
    my( $self, $point ) = @_;

    # TODO: IMPORTANT!!! This should (as all the other methods) be
    # cached and dependencies registred.

    die "Not implemented" if $point;
    my $node = $self->[NODE];

    debug_start("type_orderd_list", ' ', $self);


    # NOTE: Same type of check as in get_level()
    #
    # We can't call level() for the resources used to define level()
    #
    if( $node->[URISTR] =~ /^(@{[NS_RDF]}|@{[NS_RDFS]}|@{[NS_LS]})/o )
    {
	# Uses $Schema in Constants. Can only be scalar ref.
	my $type_uri_ref = $Schema->{$self->[NODE][URISTR]}{NS_RDF.'type'};

	# TODO: include more classes

	debug "Returning simplified list\n", 2;
	debug_end("type_orderd_list", ' ', $self);

	if( $type_uri_ref )
	  {
	    return( [$self->get( $$type_uri_ref ),
		     $self->get(NS_RDFS.'Resource')] );
	  }
	else
	  {
	    return( [$self->get(NS_RDFS.'Resource')] );
	  }
    }



#  Do we have to have all types to list the *present* defined types?
#    $node->[TYPE_ALL] or $self->init_types;

    my @types = ();
    my %included; # Keep track of included types

    # Sorting algorithm based on FMTYEWTK, sort, code 3.5
    #
    my @ot= map $self->get_context_by_id($_), keys %{$node->[TYPE]};
    my $level = $self->get( NS_LS.'level' );
    my @tl = map $_->arc_obj_value($level), @ot;

    foreach my $type (@ot[ sort {$tl[$b] <=> $tl[$a] } 0..$#ot ])
    {
	# See Constants TYPE
	push @types, $type unless $included{$type->[NODE][ID]};
	$included{$type->[NODE][ID]}++;
    }

    debug_end("type_orderd_list", ' ', $self);
    return( \@types );
}


sub changed
{
    my( $self, $parts ) = @_;

    debug_start("changed", ' ', $self);

    $parts = [$parts] unless ref $parts eq 'ARRAY';

    debug "  ( @$parts )\n", 2;



    foreach my $part ( @$parts )
    {
	if( $part eq 'selection' )
	{
	    $self->[NODE][CONTENT_ALL] = 0;
	}
	else
	{
	    die "Changing '$part' not implemented";
	}

	if( my $decides = $self->[NODE][DECIDES]{$part} )
	{
	    foreach my $obj_id ( keys %$decides )
	    {
		my $obj = $self->get_context_by_id( $obj_id );
		foreach my $callback ( keys %{$decides->{$obj_id}} )
		{
		    next unless $callback;

		    my @wanted = ();
		    foreach my $func_id ( %{$decides->{$obj_id}{$callback}} )
		    {
			my $p = $decides->{$obj_id}{$callback}{$func_id};
			next unless $p;
			die "faulty format: $p" unless ref $p eq 'ARRAY';
			push @wanted, @$p;
		    }

		    if( $callback eq 'init_dyn_rev_types' )
		    {
			$obj->[NODE][REV_TYPE_ALL] = 1
			  if $obj->[NODE][REV_TYPE_ALL] > 1;
		    }
		    elsif( $callback eq 'init_rev_subjs' )
		    {
			$obj->[NODE][REV_SUBJ_ALL] = 1
			  if $obj->[NODE][REV_SUBJ_ALL] > 1;

			my @pred_id_list = map $_->[ID], @wanted;
			my $rsp = $obj->[NODE][REV_SUBJ_PREDS];
			unless( @pred_id_list )
			{
			    @pred_id_list = keys %$rsp;
			}
			foreach my $pred_id (@pred_id_list)
			{
			    $rsp->{$pred_id} = 1
			      if $rsp->{$pred_id} > 1;
			}

		    }
		    else
		    {
			die "Callback '$callback' not implemented";
		    }

		    # We shoulden't have to do this now
		    #
		    # no strict 'refs';
		    # debug "Calling callback $callback\n", 2;
		    # &{$callback}($obj, \@point);
		}
	    }
	}
    }



    debug_end("changed", ' ', $self);
    return(1);
}


##################################################################

# The alternative selectors:
#
#   arc               subj-arcs
#   arc_obj           subj-arcs objs
#   arc_obj_list      subj-arcs objs list
#   sel_arc           container subj-arcs
#   sel_obj           container arcs objs
#   sel_arc_obj       container subj-arcs objs
#   type              res types
#   sel_type          container res types
#   rev_arc           obj-arcs
#   arc_subj          obj-arcs subjs
#   sel_rev_arc       container obj-arcs
#   sel_subj          containers arcs subjs
#   sel_arc_subj      container obj-arcs subjs
#   rev_type          res rev_types
#   sel_rev_type      container res rev_types
#   li                container res
#   rev_li            res container
#   sel               container res
#   rev_sel           res container

sub type
{
    my( $self, $point ) = @_;

    debug_start("type", ' ', $self);

    my $node = $self->[NODE];

    $node->[TYPE_ALL] == 2 or $self->init_types;

    # TODO: Insert the query in the selection, rather than the query
    # result

    my %objs = ();
    foreach my $obj_id ( keys %{$node->[TYPE]} )
    {
	# This includes types from all models
	foreach my $model_id ( keys %{$node->[TYPE]{$obj_id}})
	{
	    if( $node->[TYPE]{$obj_id}{$model_id} )
	    {
		$objs{$obj_id} = $self->get_node_by_id( $obj_id );
	    }
	}
    }

    my $selection = $self->declare_selection( [values %objs] );

    if( $point )
    {
	$selection = $selection->sel($point);
    }

    debug_end("type", ' ', $self);
    return( $selection );
}


sub rev_type
{
    my( $self, $point ) = @_;

    die "Not implemented" if $point;

    debug_start("rev_type", ' ', $self);

    $self->[NODE][REV_TYPE_ALL] == 2 or $self->init_rev_types;

    # TODO: Insert the query in the selection, rather than the query
    # result

    my %subjs = ();
    foreach my $subj_id ( keys %{$self->[NODE][REV_TYPE]} )
    {
	# This includes types from all models
	foreach my $model_id ( keys %{$self->[NODE][REV_TYPE]{$subj_id}})
	{
	    if( $self->[NODE][REV_TYPE]{$subj_id}{$model_id} )
	    {
		$subjs{$subj_id} = $self->get_node_by_id( $subj_id );
	    }
	}
    }

    my $selection = $self->declare_selection( [values %subjs] );

    debug_end("rev_type", ' ', $self);
    return( $selection );
}


sub arc
{
    my( $self, $point, $known ) = @_;

    debug_start( "arc", ' ', $self );

    my $node = $self->[NODE];
   $known ||= 0; # Should only known arcs be listed?

    unless( ref $point )
    {
	unless( defined $point )
	{
	    # With no defined point, all arcs is to be returned
	    #
	    $node->[REV_SUBJ_ALL] == 2 or $known or $self->init_rev_subjs;

	    # TODO: Insert the query in the selection, rather than the
	    # query result
	    #
	    my $arcs = [];
	    foreach my $pred_id ( keys %{$node->[REV_SUBJ]} )
	    {
		foreach my $arc_node ( @{$node->[REV_SUBJ]{$pred_id}} )
		{
		    push @$arcs, $arc_node;
		}
	    }
	    my $selection = $self->declare_selection( $arcs );

	    debug_end("arc", ' ', $self);
	    return $selection;
	}
	$point = $self->get( $point );
    }

    # Take action depending on $point
    #
    # Return all arcs with this property
    if( ref $point eq 'RDF::Service::Context' )
    {
	debug "   ( $point->[NODE][URISTR] )\n", 1;

	$known or $self->init_rev_subjs( [$point->[NODE]] );


	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $arcs = [];
	foreach my $arc_node (
	      @{$node->[REV_SUBJ]{$point->[NODE][ID]}}
	     )
	{
	    push @$arcs, $arc_node;
	}
	my $selection = $self->declare_selection( $arcs );

	debug_end("arc", ' ', $self);
	return $selection;
    }
    # Return all arcs with with these preds/objs
    elsif( ref $point eq 'HASH' )
    {
	# TODO: Use special indexex, combined indexes or ordinary
	# indexes in the form of keyd selections. Start with pred, if
	# existing

	# For now, just turn this to a sel request for all the props
	# of self

	my $selection = $self->arc->sel($point);
	debug_end("arc", ' ', $self);
	return $selection;
    }
    else
    {
	die "not implemented";
    }
}

sub arc_subj
{
    my( $self, $point ) = @_;

    # Default $point to be a property resource
    #
    unless( ref $point )
    {
	unless( defined $point )
	{
	    die "Not implemented";
	}
	$point = $self->get( $point );
    }

    debug_start( "arc_subj", ' ', $self );
    debug "   ( $point->[NODE][URISTR] )\n", 1;

    # Take action depending on $point
    #
    if( ref $point eq 'RDF::Service::Context' ) # property
    {
	# TODO: Check for == 2, and defined
	$self->init_rev_objs( $point ) unless
	  $self->[NODE][REV_OBJ_PREDS]{$point->[NODE][ID]};

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $subjs = [];
	if( $self->[NODE][REV_OBJ]{$point->[NODE][ID]} )
	{
	    foreach my $arc_node (
		  @{$self->[NODE][REV_OBJ]{$point->[NODE][ID]}}
		 )
	    {
		push @$subjs, $arc_node->[SUBJ];
	    }
	}
	my $selection = $self->declare_selection( $subjs );

	debug_end("arc_subj", ' ', $self);
	return $selection;
    }
    else
    {
	die "not implemented";
    }
    die "What???";
}

sub arc_pred
{
    my( $self, $point ) = @_;

    debug_start( "arc_pred", ' ', $self );

    if( not defined $point )
    {
	$self->[NODE][REV_SUBJ_ALL] == 2 or $self->init_rev_subjs;

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $preds = [];
	foreach my $pred_id ( keys %{$self->[NODE][REV_SUBJ]} )
	{
	    push @$preds, $self->get_node_by_id($pred_id);
	}
	my $selection = $self->declare_selection( $preds );

	debug_end("arc_pred", ' ', $self);
	return $selection;
    }
    else
    {
	die "not implemented";
    }
    die "What???";
}

sub arc_obj
{
    my( $self, $point, $init_level ) = @_;
    #
    # $init_level; 1=static, 2=dynamic
    $init_level ||= 2;

    # Default $point to be a property resource
    #
    unless( ref $point )
    {
	unless( defined $point )
	{
	    warn "*** Failed\n";
	    warn "*** Called $self->[NODE][URISTR] with ( $point )\n";
	    croak "arc_obj ( $self->[NODE][URISTR] ) without point not implemented";
	}
	$point = $self->get( $point );
    }

    debug_start( "arc_obj", ' ', $self );
    debug "   ( $point->[NODE][URISTR] )\n", 1;

    # Take action depending on $point
    #
    if( ref $point eq 'RDF::Service::Context' ) # property
    {
	unless( $self->[NODE][REV_SUBJ_PREDS]{$point->[NODE][ID]} and
		  $self->[NODE][REV_SUBJ_PREDS]{$point->[NODE][ID]} >= $init_level )
	{
	    $self->init_rev_subjs( [$point->[NODE]] );
	}

	unless( defined $self->[NODE][REV_SUBJ]{$point->[NODE][ID]} )
	{
	    debug "Resource doesn't have any $point->[NODE][URISTR]!\n", 2;
	    debug_end("arc_obj", ' ', $self);
	    return $self->declare_selection( [] );
	}

	# TODO: Insert the query in the selection, rather than the
	# query result
	#
	my $objs = [];
	debug "Result:\n", 3;
	foreach my $arc_node (
	      @{$self->[NODE][REV_SUBJ]{$point->[NODE][ID]}}
	     )
	{
	    push @$objs, $arc_node->[OBJ];
	    debug "  $arc_node->[OBJ][URISTR]\n", 3;
	}
	my $selection = $self->declare_selection( $objs );

	debug_end("arc_obj", ' ', $self);
	return $selection;
    }
    else
    {
	die "not implemented";
    }
    die "What???";
}

sub arc_obj_list
{
    my( $self, $point ) = @_;

    # Default $point to be a property resource
    #
    unless( ref $point )
    {
	unless( defined $point )
	{
	    die "Not implemented";
	}
	$point = $self->get( $point );
    }

    debug_start( "arc_obj_list", ' ', $self );
    debug "   ( $point->[NODE][URISTR] )\n", 1;

    # Take action depending on $point
    #
    if( ref $point eq 'RDF::Service::Context' ) # property
    {
	$self->init_rev_subjs( [$point->[NODE]] );

	unless( defined $self->[NODE][REV_SUBJ]{$point->[NODE][ID]} )
	{
	    debug "  found nothing\n", 2;
	    debug_end("arc_obj_list", ' ', $self);
	    return [];
	}

	my $objs = [];
	foreach my $arc_node (
	      @{$self->[NODE][REV_SUBJ]{$point->[NODE][ID]}}
	     )
	{
	    my $obj = $self->new( $arc_node )->obj;
	    debug "  found $obj->[NODE][URISTR]\n", 2;
	    push @$objs, $obj;
	}

	debug_end("arc_obj_list", ' ', $self);
	return $objs;
    }
    else
    {
	die "not implemented";
    }
    die "What???";
}

sub arc_obj_value
{
    my( $self, $point ) = @_;

    # Default $point to be a property resource
    #
    unless( ref $point )
    {
	unless( defined $point )
	{
	    die "Not implemented";
	}
	$point = $self->get( $point );
    }

    debug_start( "arc_obj_value", ' ', $self );
    debug "   ( $point->[NODE][URISTR] )\n", 1;

    # Take action depending on $point
    #
    if( ref $point eq 'RDF::Service::Context' ) # property
    {
	# TODO: Only call init_rev_subjs if the point is not
	# initialized.
	$self->init_rev_subjs( [$point->[NODE]] );

	my $props = $self->[NODE][REV_SUBJ]{$point->[NODE][ID]};

	unless( defined  $props )
	{
	    # No property defined
	    debug "Returning undef\n", 1;
	    debug_end("arc_obj_value", ' ', $self);
	    return undef;
	}
	if( $props->[1] )
	{
	    warn "More than one property found of ".
	      $point->[NODE][URISTR] . " for ".
		$self->[NODE][URISTR] . "\n";
	    foreach my $prop ( @$props )
	    {
#		warn "\t $prop\n";
		if( $prop->[OBJ][VALUE] )
		{
		    warn "\tvalue: ${$prop->[OBJ][VALUE]}\n";
		}
		else
		{
		    warn "\tWe expected $prop->[OBJ][URISTR] to be a literal\n";
		    warn "\t\tBut VALUE is undefined!\n";
		}
	    }
	    confess;
	}
	if( my $valref = $props->[0][OBJ][VALUE] )
	{
	    if( $DEBUG >= 2 )
	    {
		my $val = substr($$valref, 0, 40);
		debug "Returning '$$valref'\n";
	    }
	    debug_end("arc_obj_value", ' ', $self);
	    return $$valref;
	}
	else
	{
	    die "Poperty has no value\n";
	}
    }
    else
    {
	die "not implemented";
    }
    die "What???";
}

sub selector
{
    die "not imlemented";

    my $point;
    if( not defined $point ) # Return all arcs
    {
    }
    elsif( ref $point eq 'ARRAY' ) # Return ORed elements
    {
    }
    elsif( ref $point eq 'HASH' ) # Return ANDed elements
    {
    }
    elsif( ref $point eq 'RDF::Service::Context' )
    {
    }
    else
    {
	die "Malformed entry";
    }
}

sub set_class
{
    my( $self, $cprops, $props ) = @_;
    die "Not implemented";
}

sub set
{
    my( $self, $types, $props ) = @_;

    # This is practicaly the same as declare_self.  set() updates the
    # data in the interfaces.

    debug_start("set", ' ', $self);

    # Should each type and property only be saved in the first best
    # interface and not saved in the following interfaces?  Yes!
    #
    # The types and props taken by one interface must be marked so
    # that the next interface doesn't handle them. This could be done
    # by modifying the arguments $types and $props to exclude those
    # that has been taken care of.

    $self->set_types( $types, 1);

    # This is acceptable because it will almost only be used on
    # level 0
    $self->[NODE][REV_SUBJ_ALL] == 2 or $self->init_rev_subjs;
    $self->set_props( $props, 2);

    $self->store;

    debug_end("set", ' ', $self);
    return $self;
}

sub set_types
{
    my( $self, $types, $trim, $solid ) = @_;
    #
    # Remove existing types not mentioned if $trim

    debug_start("set_types", ' ', $self);

    my $node = $self->[NODE];
    my $model = $self->[WMODEL][NODE];
    $solid ||= 0;

    if( $DEBUG )
    {
	ref $model eq "RDF::Service::Resource" or
	  confess "Bad model ($model)";

    }

    # NOTE: It would be more efficient to not initiate the types just
    # because we want to set a type.  Waite with that until we want to
    # know all types.  But that would mean that we doesn't know if we
    # should add or subtract types.  Ie, we can't do that.


    # TODO: Maby do the same change as for set_props: ie, move
    # init_types out of this function.
    $node->[TYPE_ALL] == 2 or $self->init_types;

    my @add_types;
    my %del_types;
    foreach my $type ( @{$self->type_orderd_list} )
    {
	if( $node->[TYPE]{$type->[NODE][ID]}{$model->[ID]} )
	{
	    $del_types{$type->[NODE][ID]} = $type;
	}
    }

    foreach my $type ( @$types )
    {
	$type = $self->get( $type ) unless ref $type;
	if ( $del_types{ $type->[NODE][ID] } )
	{
	    delete $del_types{ $type->[NODE][ID] };
	}
	else
	{
	    push @add_types, $type;
	}
    }

    if ( @add_types )
    {
	# Will only add each type in one interface
	$self->declare_add_types( [@add_types], undef, $solid );
    }

    if ( $trim and %del_types )
    {
	# Will delete types from all interfaces
	$self->declare_del_types( [values %del_types] );
	$self->remove_types( [values %del_types] ); # Was: unless local_changes
    }

    unless( $solid )
    {
	$node->[TYPE_SOLID] = 0;
    }

    debug_end("set_types", ' ', $self);
    return $self;
}

sub set_rev_types
{
    my( $self, $rev_types, $trim, $solid, $model ) = @_;
    #
    # Remove existing rev_types not mentioned if $trim

    debug_start("set_rev_types", ' ', $self);

    my $node = $self->[NODE];
    $model ||= $self->[WMODEL][NODE];
    $solid ||= 0;

    if( $DEBUG )
    {
	ref $model eq "RDF::Service::Resource" or
	  confess "Bad model ($model)";

    }

    # NOTE: init_rev_types should be called before set_rev_types

    my @add_rev_types;
    my %del_rev_types;
    foreach my $res_id ( keys %{$node->[REV_TYPE]} )
    {
	if( $node->[REV_TYPE]{$res_id}{$model->[ID]} )
	{
	    $del_rev_types{$res_id} = $self->get_context_by_id($res_id);
	}
    }

    foreach my $res ( @$rev_types )
    {
	$res = $self->get( $res ) unless ref $res;
	if ( $del_rev_types{ $res->[NODE][ID] } )
	{
	    delete $del_rev_types{ $res->[NODE][ID] };
	}
	else
	{
	    push @add_rev_types, $res;
	}
    }

    foreach my $res ( @add_rev_types )
    {
	$res->declare_add_types( [$self], $model, $solid );
    }

    if ( $trim and %del_rev_types )
    {
	foreach my $res ( values %del_rev_types )
	{
	    $res->declare_del_types( [$self], $model );
	    $res->remove_types( [$self], $model );
	}
    }

    unless( $solid ) # TODO: Is this right?
    {
	$node->[REV_TYPE_SOLID] = 0;
    }

    debug_end("set_rev_types", ' ', $self);
    return $self;
}

sub set_props
{
    my( $self, $props, $trim, $solid, $model, $known ) = @_;
    #
    # Add props not yet existing.  Only operate within WMODEL.
    #
    # $trim == 0;  Only add properties
    #
    # $trim == 1; Update mentioned properties with new value. Existing
    #             properties with a pred not mentioned in $props will
    #             not be removed.
    #
    # $trim == 2;  Replace all properties with the new ones
    #
    # The props will be compared with KNOWN existing props.  Calling
    # function should make the necessary initialization.  (This
    # because this function will be used by the initialization of
    # dynamic properties.)
    #
    #
    # $props->{$pred_uri => [ $obj ] }
    #
    # Pass scalar ref objs through? NO, can't do that!

    # TODO: Return if a change was made or not? (To be used in
    # resetting dynamic props)


    debug_start("set_props", ' ', $self);

    my $node = $self->[NODE];
    $model ||= $self->[WMODEL][NODE];
    $solid ||= 0;
    $trim  ||= 0;
    $known ||= 0;

    my %add_props; # $add_props->{$pred_id}[$obj]
    my %del_props; # $del_props->{$pred_id}{$obj_id => $arc}

    # This will hold present properties in the model
    # that does not exist in the new set of
    # properties.  Start by adding all present properties and remove
    # the ones that exist in the new property list.

    foreach my $arc ( @{$self->arc(undef, $known)->list} )
    {
	if( $arc->[NODE][MODEL][ID] == $model->[ID] )
	{
	    $del_props{$arc->[NODE][PRED][ID]}{$arc->[NODE][OBJ][ID]} = $arc;
	}
    }


    # Iterate through the submitted props, by pred and obj
    debug "Setting up adds/removes\n",2;
    foreach my $pred_key ( keys %$props )
    {
	my $pred_id;
	# Checks for abbrevations
	if( my $x = $self->[SESSION][ABBREV]{$pred_key} )
	{
	    debug "abbrev for $x->[NODE][URISTR]\n", 2;
	    $pred_id = $x->[NODE][ID];
	}
	else
	{
	    $pred_id = uri2id($pred_key);
	}

	debug "  Checking $pred_key\n", 2;


	# Normalize obj part to a list ref
	unless( ref $props->{$pred_key} eq 'ARRAY' )
	{
	    $props->{$pred_key} = [$props->{$pred_key}];
	}

	# handle implicit properties
	#
	# TODO: Support URIs for implicit properties
	#


	foreach my $obj ( @{ $props->{$pred_key} } )
	{

	    # Is the object a literal?
	    if( not ref $obj )
	    {
		if( $DEBUG )
		{
		    unless( $obj =~ /^(http|value):/ )
		    {
			confess "The uri '$obj' seem to be a literal";
		    }
		}
		$obj = $self->get( $obj );
	    }
	    elsif( ref $obj eq 'SCALAR' )
	    {
		debug "  Creating literal '$$obj'\n", 1;

		# Warning. Previouslu wrote this as \$obj.  It took me
		# over a day to find this and realize that the
		# reasigning of $obj would overwrite the created
		# literal value, creating a self-reference
		#
		$obj = $self->declare_literal($obj);
		$obj->[NODE][SOLID] = $solid;
		debug "Changing SOLID to $solid for $obj->[NODE][URISTR] ".
		  "IDS $obj->[NODE][IDS]\n", 3;

		# The SOLID is set to $solid. If this literal shouldn't be
		# saved in any interface, the base interface should
		# take care of the literal.  The storage of the
		# literal should be done via the arc that points at
		# it.  It should suffice to handle the arc and at that
		# time declare the literal solid in case it is saved
		# together with the arc.
	    }
	    elsif( ref $obj ne "RDF::Service::Context" )
	    {
		die "Each obj should be context obj, scalar ref or res uri";
	    }

	    if( $DEBUG )
	    {
		if( $obj->[NODE][VALUE] )
		{
		    unless( ref($obj->[NODE][VALUE]) eq 'SCALAR')
		    {
			confess "Bad value for $obj->[NODE][URISTR] ( ".
			  ref($obj->[NODE][VALUE])." ne 'SCALAR' )";
		    }
		}
	    }


	    # TODO: Maby check if the values is the same even if the
	    # literal URIs differ?  No, use the same URI if this
	    # matters!

	    debug "    Object $obj->[NODE][URISTR]\n", 2;

	    # Does this resource already have the arc?
	    if( $del_props{$pred_id}{$obj->[NODE][ID]} )
	    {
		# Keep this property
		debug "      Keep object\n", 2;
		delete $del_props{$pred_id}{$obj->[NODE][ID]};
	    }
	    else
	    {
		# Add this property
		debug "      Add object\n", 2;
		push @{$add_props{$pred_id}}, $obj;
	    }
	}
    }

    if( %del_props )
    {
	# Will delete props from all interfaces
	foreach my $pred_id ( keys %del_props )
	{
	    if( $DEBUG )
	    {
		my $pred_uri = &id2uri($pred_id);
		debug "Del checking $pred_uri\n", 1;
	    }

	    # Remove the pred objs if other pred objs was specified,
	    # or if $trim is set, in case we remove everything not
	    # specified
	    #
	    if( $DEBUG >= 2 )
	    {
		unless( $trim )
		{
		    debug "  Skipping delcheck\n";
		}

		my $nokeys = keys %{ $del_props{$pred_id} };
		debug "  $nokeys objs found\n";
	    }

	    next unless $trim >= 1;
	    next unless $trim >= 2 or $add_props{$pred_id};

	    foreach my $obj_id ( keys %{ $del_props{$pred_id} } )
	    {
		debug "  Deleting node ".
		  $del_props{$pred_id}{$obj_id}[NODE][URISTR]."\n", 2;

		$del_props{$pred_id}{$obj_id}->delete_node();
	    }
	}
    }

    if( %add_props )
    {
	# Will only add each prop in one interface
	foreach my $pred_id ( keys %add_props )
	{
	    my $pred = $self->get_context_by_id($pred_id);
	    foreach my $obj ( @{ $add_props{$pred_id} } )
	    {
		$self->declare_add_prop(
		      $pred, $obj, undef, $model, $solid);
	    }
	}
    }

    debug_end("set_props", ' ', $self);
    return $self;
}

sub set_literal
{
    my( $self, $lit_str_ref ) = @_;

    debug_start("set_literal", ' ', $self);
    debug "   Change to ($$lit_str_ref)\n", 1;

    # TODO: make sure you have the right to update this literal!

    $self->declare_literal( $lit_str_ref, $self,  );
    $self->store_node;

    debug_end("set_literal", ' ', $self);
}

sub set_label
{
    my( $self, $val ) = @_;

    die "deprecated";

    # For simplicity, we only use one label.  Intended for system
    # administration.

    if( ref $val eq 'ARRAY' )
    {
	$val = $val->[0];
    }
    if( ref $val eq 'RDF::Service::Context' )
    {
#	$val = $val->[NODE][VALUE];
    }
    if( ref $val eq 'SCALAR' )
    {
	$val = $$val;
    }

#    $self->[NODE][LABEL] = $val || '';
}


sub types_as_string
{
    my( $self ) = @_;
    #
#   die $self->uri."--::".Dumper($self->[TYPES]);
    my $result = "";
    my $type_ref = $self->[NODE][TYPE];
    foreach my $type_id ( sort keys %{$type_ref} )
    {
	my $type_uristr = id2uri( $type_id );
	$result .= "t $type_uristr\n";
	foreach my $model_id ( sort keys
				 %{$type_ref->{$type_id}} )
	{
	    my $model_uristr = id2uri( $model_id );
	    my $solid = $type_ref->{$type_id}{$model_id} - 1;
	    $result .= "  m $model_uristr  SOLID $solid\n";
	}

    }

    return $result;
}


sub to_string
{
    my( $self ) = @_;

    # Old!

    my $str = "";
    no strict 'refs';

    $str.="TYPES\t: ". $self->types_as_string ."\n";

    foreach my $attrib (qw( IDS URISTR ID LABEL PREFIX MODULE_NAME ))
    {
	$self->[NODE][&{$attrib}] and $str.="$attrib\t:".
	    $self->[NODE][&{$attrib}] ."\n";
    }

    foreach my $attrib (qw( NS MODEL ALIASFOR LANG PRED SUBJ OBJ ))
    {
#	my $dd = Data::Dumper->new([$self->[&{$attrib}]]);
#	$str.=Dumper($dd->Values)."\n\n\n";
#	$self->[&{$attrib}] and $str.="$attrib\t:".Dumper($self->[&{$attrib}])."\n";
	$self->[NODE][&{$attrib}] and $str.="$attrib\t:".
	    ($self->[NODE][&{$attrib}][URISTR]||"no value")."\n";
    }

    return $str;
}


########################################################
#
# Wrapper methods for the interfaces
#
#    &RDF::Service::Dispatcher::go(shift, $AUTOLOAD, @_);

# TODO:  Should not mark that ALL data has been initialized if
# init_types was called from a function in the process of adding new
# types.  This could be done with a memory of previous calls in the
# CONTEXT.

# NB!  Expect all initiated data to be solid!

# NB!  Set ALL after a call to init, unless thare are additionall data
# to be set.

sub init_types
{
    my( $self ) = shift;

    debug_start('init_types', ' ', $self );

    my $node = $self->[NODE];
    my $prefix_key = $node->[IDS].'/'.$node->find_prefix_id;


    unless( $node->[TYPE_ALL] )
    {
	# Create a temporary JUMPTABLE in order to call the
	# init_types() function in the correct interfaces

	# Set the first type: Resource
	# TODO: Make all things type resource implicitly!
	#
	my $c_resource = $self->get( NS_RDFS.'Resource' );
	my $model_id = uri2id(NS_RDFS);
	$node->[TYPE]{$c_resource->[NODE][ID]}{$model_id}=2;

	# JUMPTABLE based on RDFS:Resource
	#
	if(not defined $JumpJumpTable{$prefix_key})
	{
	    # Create the jumptable
	    create_jumptable($self, $prefix_key);
	}
	$node->[JUMPTABLE] = $JumpJumpTable{$prefix_key};


	go($self, 'init_src_types') unless $node->[LOCAL];
	$node->[TYPE_ALL] = 1;
    }

    my $previous = $prefix_key;
    my $key = $prefix_key . '/' .
      join('-', map $_->[NODE][ID],
	   @{$self->type_orderd_list});

    my $counter = 0;
    #
    while( $key ne $previous )
    {
	$previous = $key;
	die "Infinite loop in type initialization" if ++$counter >= 15;

	debug "New key no $counter is $key\n", 3;

	if(not defined $JumpJumpTable{$key})
	{
	    create_jumptable($self, $key);
	}

	$node->[JUMPTABLE] = $JumpJumpTable{$key};
	$node->[DYNTABLE] = $JumpPropTable{$key};
	if( $DEBUG >= 3 )
	{
	    debug "The types of $node->[URISTR] is:\n";
	    debug $self->types_as_string;

	    debug "The new DYNTABLE looks like this:\n";
	    foreach my $func ( keys %{$node->[DYNTABLE]} )
	    {
		debug "  $func\n";
	    }
	}

	go($self, 'init_dyn_types');

	$key = $prefix_key . '/' .
	  join('-', map $_->[NODE][ID],
	       @{$self->type_orderd_list});

	### DEBUG
	debug "The new key $key consists of:\n";
	debug( join(' - ', map $_->[NODE][URISTR],
	       @{$self->type_orderd_list})." ***\n");

    }
    $node->[TYPE_ALL] = 2;

    debug_end('init_types', ' ', $self );
}

sub init_rev_types
{
    my( $self ) = shift;

    return if $self->[NODE][REV_TYPE_ALL] == 2;

    debug_start("init_rev_types", ' ', $self );

    go($self, 'init_src_rev_types', @_) unless $self->[NODE][LOCAL];
    go($self, 'init_dyn_rev_types', @_);
    $self->[NODE][REV_TYPE_ALL] = 2;

    debug_end("init_rev_types", ' ', $self );
}

sub init_rev_subjs
{
    my( $self, $wanted ) = @_;
    #
    # $wanted is an array ref of predicate nodes

    return if $self->[NODE][REV_SUBJ_ALL] == 2;

    debug_start("init_rev_subjs", ' ', $self );

    my $node = $self->[NODE];
    $wanted ||= [];

    # TODO: init_rev_subjs is called about a gazillion times just to
    # do nothing at all.  We would like to make futher calles to see
    # wether the wanted property has been initialized.  The problem
    # here is that it require one check for existence and another
    # check for status.

    if( @$wanted )
    {
	confess "Wrong type in wanted: $wanted->[0]"
	  if ref $wanted->[0] ne 'RDF::Service::Resource';

	# Find out if we need to init_src_rev_subjs
	#
	my $got_preds = 1;
	debug "Wanted:\n", 2;
	foreach my $pred_node ( @$wanted )
	{
	    debug "  $pred_node->[URISTR]\n", 2;

	    unless( $node->[REV_SUBJ_PREDS]{$pred_node->[ID]} )
	    {
		$got_preds = 0;
	    }
	}

	unless( $got_preds )
	{

	    # TODO: init_src_rev_subjs($target) is a interface
	    # function that creates one arc for each stating with a
	    # predicate mathing the $target.  The core system
	    # remembers then the property for the target has been
	    # fetched and doesent call the dunction again if the whole
	    # target already has been aquired.
	    #
	    # But if only a part of the target has been aquired, the
	    # function will be called again.  The result can bee that
	    # statings for a specific predicate will be added
	    # multipple times.  In the case for partially initialized
	    # targtets, this could be avoided if the system removes
	    # the already initialized predicates from the target
	    # before it calls the function.
	    #
	    # But that soulution only works if the function only adds
	    # statings for the target properties.  But we want the
	    # interfaces to be able to add all related statings in the
	    # same call, in order to minimize the number of calles to
	    # the backend.
	    #
	    # But do we want the core to remember what statings has
	    # been added by which interface and to keep tabs on wheter
	    # a certain interface has added all statings for a
	    # specific property?  Today, we keep tags for each
	    # property in each resource.  This would add yet another
	    # level of administrative resource metadata.

	    go($self, 'init_src_rev_subjs', $wanted)
	      unless $node->[LOCAL];

	    foreach my $pred_node ( @$wanted )
	    {
		$node->[REV_SUBJ_PREDS]{$pred_node->[ID]} ||= 1;
	    }
	}
    }
    else
    {
	# Because DYNTABLE depends on TYPE_ALL
	$self->init_types unless $node->[TYPE_ALL] == 2;

	if( not defined $node->[DYNTABLE] )
	{
	    &select_jumptable( $self );
	}
	@$wanted = map $self->get_node($_), keys %{$node->[DYNTABLE]};

	if( $DEBUG > 2 )
	{
	    debug "Types for $node->[URISTR] is:\n";
	    debug $self->types_as_string;

	    debug "Wanted: EVERYTHING, ie:\n";
	    foreach my $pred_node ( @$wanted )
	    {
		debug "  $pred_node->[URISTR]\n";
	    }
	}

	unless( $node->[REV_SUBJ_ALL] >= 1 )
	{
	    go($self, 'init_src_rev_subjs')
	      unless $node->[LOCAL];
	    $node->[REV_SUBJ_ALL] = 1;

	    foreach my $pred_id ( keys %{$node->[REV_SUBJ]} )
	    {
		$node->[REV_SUBJ_PREDS]{$pred_id} ||= 1;
	    }
	}
    }


    debug "..DYNTABLE start\n", 2;

  DYNLOOP:
    foreach my $pred_node ( @$wanted )
    {
	if( $node->[REV_SUBJ_PREDS]{$pred_node->[ID]} and
	    $node->[REV_SUBJ_PREDS]{$pred_node->[ID]} == 2 )
	{
	    next;
	}

	my $pred_uristr = $pred_node->[URISTR];

	# Also used in Dispatcher for method calls
	#
	my $call_key = "$pred_uristr $self->[NODE] @$wanted";
	foreach( @{$self->[HISTORY]} )
	{
	    if( $_ eq $call_key )
	    {
		debug "Recursive call '$call_key' skipped", 2;
		next DYNLOOP;
	    }
	}
#	warn "---<<< called $call_key >>>---\n";
	push @{$self->[HISTORY]}, $call_key;


	my $coderef = $node->[DYNTABLE]{$pred_uristr};
	my $success = 0;

	for( my $i=0; $i<= $#$coderef; $i++ )
	{
	    debug_start( $pred_uristr, $i, $self );
	    debug "..Calling dynprop $coderef->[$i][1][URISTR]\n", 2;

	    # The second parameter is the interface object
	    my( $res ) = &{$coderef->[$i][0]}($self,
					      $coderef->[$i][1],
					      $self->new($pred_node),
					      $wanted);

	    debug_end( $pred_uristr, $i, $self );

	    unless( defined $res )
	    {
		die "undef return value";
	    }
	    elsif( $res == 0 ) #No success, call next
	    {
		# Do nothing
	    }
	    elsif( $res == 1 ) #Final, return
	    {
		$success ++;
		last;
	    }
	    elsif( $res == 3 ) #Success, call next
	    {
		$success ++;
	    }
	    else
	    {
		die "Illegal return value: $res";
	    }
	}

	# Falling back one step  (not one LEVEL)
	pop @{$self->[HISTORY]};


	# We now have all preds for this node
	$node->[REV_SUBJ_PREDS]{$pred_node->[ID]} = 2;
    }
    debug "..DYNTABLE done\n", 2;

    unless( @$wanted )
    {
	$node->[REV_SUBJ_ALL] = 2;
    }

    debug_end("init_rev_subjs", ' ', $self );
}

sub init_rev_objs
{
    my( $self ) = shift;

    debug_start("init_rev_objs", ' ', $self );

    go($self, 'init_src_rev_objs', @_) unless $self->[NODE][LOCAL];

    # TODO: Same as init_rev_subjs, but reverse

    $self->[NODE][REV_OBJ_ALL] = 2;

    debug_end("init_rev_objs", ' ', $self );
}

sub init_rev_preds
{
    my( $self ) = shift;

    debug_start("init_rev_preds", ' ', $self );

    go($self, 'init_src_rev_preds', @_) unless $self->[NODE][LOCAL];

    # TODO: expand, like init_rev_subjs

    $self->[NODE][REV_PRED_ALL] = 2;

    debug_end("init_rev_preds", ' ', $self );
}




sub store_types
{
    my( $self, @args ) = @_;

    debug_start("store_types", ' ', $self );


    if( $DEBUG >= 4 )
    {
	debug "HISTORY\n";
	foreach( @{$self->[HISTORY]} )
	{
	    debug "    $_\n";
	}
    }


    my $node = $self->[NODE];
    $node->[TYPE_ALL] >= 1 or $self->init_types();

    # Check if all types are solid
    #
    my $unsaved = 0;
  CHECK:
    foreach my $type_id ( keys %{$node->[TYPE]} )
    {
	my $type = $self->get_context_by_id( $type_id );
	foreach my $model_id ( keys %{$node->[TYPE]{$type_id}} )
	{
	    my $model = $self->get_context_by_id( $model_id )->[NODE];
	    unless( $node->[TYPE]{$type_id}{$model_id} == 2 )
	    {
		$unsaved ++;
		last CHECK;
	    }
	}
    }

    if( $unsaved )
    {
	debug "GO store_types\n", 3;
	if( go($self, 'store_types', @args)  )
	{
	    $node->[TYPE_SOLID] = 1;
	}
    }
    else
    {
	$node->[TYPE_SOLID] = 1;
    }

    debug_end("store_types", ' ', $self);
}

sub store_props
{
    my( $self, @args ) = @_;
    my $node = $self->[NODE];

    # TODO: Is this necessary?
    $node->[REV_SUBJ_ALL] >= 1 or $self->init_rev_subjs();

    debug "GO store_props\n", 3;
    if( go($self, 'store_props', @args) )
    {
	$node->[REV_SUBJ_SOLID] = 1;
    }
}

sub store
{
    my( $self ) = @_;

    debug_start("store", ' ', $self);

    # TODO: Reset all other IDS caches (for this Resource)


    my $node = $self->[NODE];

    # The order of checking for a node is:
    #
    # 1. props
    # 2. types
    # 3. node
    # 4. model
    #
    # The order is significant, since the store_props and store_types
    # methods can delegate storage of specific data to the node or
    # model.


    # Save props unless they are solid
    unless( $node->[REV_SUBJ_SOLID] )
    {
	$self->store_props;
    }

    # Save types unless they are solid
    unless( $node->[TYPE_SOLID] )
    {
	$self->store_types;
    }

    unless( $node->[SOLID] )
    {
	if( $DEBUG )
	{
	    if( $node->[VALUE] )
	    {
		debug( "Node NOT solid: ${$node->[VALUE]}\n" );
	    }
	}
	$self->store_node;
    }
    else
    {
	if( $DEBUG )
	{
	    if( $node->[VALUE] )
	    {
		debug( "Node SOLID: ${$node->[VALUE]}\n" );
	    }
	}
    }



    # Also store the model
    if( $node->[MODEL] )
    {
	debug "  Is the model ($node->[URISTR]) solid?\n", 2;
	$self->get_context_by_id($node->[MODEL][ID])->store
	  unless $node->[MODEL][SOLID];
    }

    # Only saves props. Not rev props.

    debug_end("store", ' ', $self);

    return( 1 );
}



######################################################################
#
# Declaration methods should only be called from interfaces.
#

sub declare_del_types
{
    my( $self, $types, $model ) = @_;

    debug_start("declare_del_types", ' ', $self);

    my $node_type = $self->[NODE][TYPE];
    $model ||= $self->[WMODEL][NODE];
    my $model_id = $model->[ID];
    my $id = $self->[NODE][ID];

    my @ids = ();
    if( defined $types )
    {
	@ids = map $_->[NODE][ID], @$types;
    }
    else
    {
	@ids = keys %$node_type;
    }

    foreach my $class_id ( @ids )
    {
	my $class_node = $self->get_node_by_id($class_id);
	debug "  Checking $class_node->[URISTR]\n", 2;
	unless( delete $node_type->{$class_id}{$model_id} )
	{
	    debug "    Type defined in another model:\n", 2;
	    foreach my $other_model_id ( keys %{$node_type->{$class_id}} )
	    {
		my $other_model_node =
		  $self->get_node_by_id($other_model_id);
		debug "      $other_model_node->[URISTR]\n", 2;
	    }
	    next;
	}

	my $class_rev_type = $class_node->[REV_TYPE];

	debug "    Removing rev_type node\n", 2;
	if( $DEBUG )
	{
	    unless( $class_rev_type->{$id} )
	    {
		unless( $class_node->[URISTR] eq NS_RDFS.'Resource' )
		{
		    die "    There was no rev_type to remove!!\n";
		}
	    }
	}

	delete $class_rev_type->{$id}{$model_id};

	delete $node_type->{$class_id} 
	  unless keys %{$node_type->{$class_id}};

	delete $class_rev_type->{$id}
	  unless keys %{$class_rev_type->{$id}};
    }

    debug_end("declare_del_types", ' ', $self);
}

sub declare_del_rev_types
{
    my( $self, $res ) = @_;

    debug_start("declare_del_rev_types", ' ', $self);

    my $class_rev_type = $self->[NODE][REV_TYPE];
    my $model_id = $self->[WMODEL][NODE][ID];
    my $id = $self->[NODE][ID];

    my @ids = ();
    if( defined $res )
    {
	@ids = map $_->[NODE][ID], @$res;
    }
    else
    {
	@ids = keys %$class_rev_type;
    }

    foreach my $res_id ( @ids )
    {
	my $class_node = $self->get_node_by_id($res_id);
	debug "  Checking $class_node->[URISTR]\n", 2;
	unless( delete $class_rev_type->{$res_id}{$model_id} )
	{
	    next;
	}

	my $class_type = $class_node->[TYPE];

	debug "  Removing type node\n", 2;
	if( $DEBUG )
	{
	    unless( $class_type->{$id} )
	    {
		die "    There was no type to remove!!\n";
	    }
	}
	delete $class_type->{$id}{$model_id};

	delete $class_rev_type->{$res_id} 
	  unless keys %{$class_rev_type->{$res_id}};

	delete $class_type->{$id}
	  unless keys %{$class_type->{$id}};
    }

    debug_end("declare_del_rev_types", ' ', $self);
}

sub declare_literal
{
    my( $self, $lit_str_ref, $lit, $types, $props, $model ) = @_;
    #
    # - $model is a resource object
    # - $lit (uri or node or undef)
    # - $lit_str_ref will be a scalar ref
    # - $types is ref to array of type objects or undef
    # - $props is hash ref with remaining properties or undef
    # - $model is working model node

    # The URI of a static literal represents what the value
    # represents.  That is; the abstract property.  It will never
    # change.  (The literal static/dynamic type info is not stored)

    # The URI of a dynamic literal represents the property for the
    # specific subject.  The literal changes content as the subjects
    # property changes.  (The literal static/dynamic type info is not
    # stored)


    die "not implemented" if $types or $props;

    # TODO: CHECK that this resource realy is SOLID by default?

    debug_start("declare_literal", ' ', $self );

    my $local = 0;

    # $lit can be node or uristr.
    #
    unless( ref $lit )
    {
	unless( defined $lit )
	{
	    # Literal uri undefined.  By default, we eill use a static
	    # literal.  A static literal will represent a nonchanging
	    # literal value.  We locate the uri by translating the
	    # value to the corersponding value: uri.  This is only
	    # done for values less than or equal to 250 carachters
	    # (unidcode?).

	    if( length( $$lit_str_ref ) > 250 )
	    {
		$lit = NS_LD."literal/". &get_unique_id;
	    }
	    else
	    {
		use CGI;
		$lit = 'value:'.CGI::escape($$lit_str_ref);
	    }

	    $local = 1;
	}
	$lit = $self->get( $lit );
    }

    # Maby this literal already is defined?
    # TODO: Special handling of large values
    #
    if( $lit->[NODE][VALUE] and
	  ${$lit->[NODE][VALUE]} eq $$lit_str_ref )
    {
	debug_end("declare_literal", ' ', $self);
	return $lit;
    }

    if( $DEBUG )
    {
	debug "   ( $$lit_str_ref )\n", 1;

	ref $lit_str_ref eq 'SCALAR'
	  or die "Value must be a scalar reference";

	if( $$lit_str_ref =~ /^RDF/ )
	{
	    warn "*****";
	    confess "Value is $$lit_str_ref";
	}

    }


    # TODO: Set value as property if value differ among models

    my $lit_node = $lit->[NODE];

    $model ||= $self->[WMODEL][NODE];
    $lit_node->[VALUE] = $lit_str_ref;
    $lit_node->[MODEL] = $model;
    $lit_node->[LOCAL] = 1;
    $model->[REV_MODEL]{$lit_node->[ID]} = $lit_node;

    $lit->declare_add_types([NS_RDFS.'Literal'], $model, 1 );

    debug_end("declare_literal", ' ', $self);
    return $lit;
}

sub declare_selection
{
    my( $self, $content, $selection ) = @_;


    debug_start("declare_selection", ' ', $self);
    if( $DEBUG )
    {
	confess unless ref $content;
	my @con_uristr = ();
	debug "  Selection consists of:\n", 2;
	foreach my $res ( @$content )
	{
	    confess "$res no Resource"
	      unless ref $res eq "RDF::Service::Resource";
	    debug "  $res->[URISTR]\n", 2;
	}
    }

    $content ||= [];
    my $local = 0;
    my $model = $self->[WMODEL][NODE] or
      die "$self->[NODE][URISTR] doesn't have a defined model";

    unless( ref $selection )
    {
	unless( defined $selection )
	{
	    $selection = NS_LD.'selection/'.&get_unique_id;
	    $local = 1;
	}
	$selection = $self->get( $selection );
    }
#    warn "*** Selection is $selection->[NODE][URISTR]\n";

    my $selection_node = $selection->[NODE];

    $selection_node->[MODEL] = $model;
    $selection_node->[SELECTION] = $content;
    $selection_node->[LOCAL] = $local;

    # TODO: Only add if this is an addition
    $model->[REV_MODEL]{$selection_node->[ID]} = $selection_node;

    # We add container explicitly because of special handling for Selection
    $selection->declare_add_types( [NS_LS.'Selection',NS_RDFS.'Container'] );

    debug_end("declare_selection", ' ', $self);
    return $selection;
}

sub declare_node
{
    my( $self, $uri, $types, $props );

    die "Not done";
}

sub declare_add_types
{
    my( $self, $types, $model, $solid ) = @_;

    debug_start("declare_add_types", ' ', $self );

    # TODO: Should it be model instead of types?

    # TODO: type(Resource) should be added by base init_types

    # The types will be listed in order from the most specific to the
    # most general. rdfs:Resource will allways be last.  Insert
    # implicit items according to subClassOf.

    my $node = $self->[NODE];
    $model ||= $self->[WMODEL][NODE];
    $model = $self->get_node($model) unless ref $model;
    $solid ||= 0;

    if( $DEBUG )
    {
	confess "Invalid solid value: $solid" if $solid > 1;
	croak "types must be a list ref" unless ref $types;
	croak "Bad model: $model" unless
	  ref $model eq "RDF::Service::Resource";
	confess "Bad node: $node" unless
	  ref $node eq "RDF::Service::Resource";
	debug "  in model $model->[URISTR] IDS $model->[IDS]\n";
    }

    my $model_id = $model->[ID];
    foreach my $type ( @$types )
    {
	# This should update the $types listref
	#
	$type = $self->get( $type ) unless ref $type;

	# Duplicate types in the same model will merge
	#
	# SOLID = 2, NONSOLID = 1
	#
	$node->[TYPE]{$type->[NODE][ID]}{$model_id} = 1 + $solid;
	$type->[NODE][REV_TYPE]{$node->[ID]}{$model_id} = 1 + $solid;

	if( $DEBUG )
	{
	    debug("    T $type->[NODE][URISTR] ".
		    "(IDS $type->[NODE][IDS] )\n", 2);
	    if( $type->[NODE][MODEL] )
	    {
		debug("      Model of type is ".
			$type->[NODE][MODEL][URISTR] .
			  " IDS $type->[NODE][MODEL][IDS]\n", 2);
	    }
	}
    }

    # TODO: Only set this if one type was added
    #
    # NB! The model include this node in REV_MODEL if it self or any
    # of its types belongs to the model.  But the node includes the
    # model only if int's internal data belongs to that model.
    #
    $model->[REV_MODEL]{$node->[ID]} = $node;

    unless( $solid )
    {
	# Node type no longer solid. (Unsaved types)
	#
	$node->[TYPE_SOLID] = 0;
    }

    # TODO: Separate the dynamic types to a separate init_types

    debug "Adding subtypes\n", 2;

    # Add the implicit types for $node.  This is done in a second loop
    # in order to resolv cyclic dependencies.
    # TODO: Check that this generates the right result.
    #
    my $subClassOf = $self->get(NS_RDFS.'subClassOf');
    foreach my $type ( @$types )
    {
	# $types has previously (in this function) been converted from
	# URISTR to res

 	# NB!!! Special handling of some basic classes in order to
 	# avoid cyclic dependencies.  The caller must add the required
 	# subtypes, except for RDFS:Resource.  (Especiellay for Selection)
 	#
	my $type_node = $type->[NODE];
 	next if $type_node->[URISTR] eq NS_RDFS.'Literal';
 	next if $type_node->[URISTR] eq NS_RDFS.'Class';
 	next if $type_node->[URISTR] eq NS_RDFS.'Resource';
 	next if $type_node->[URISTR] eq NS_RDF.'Statement';
 	next if $type_node->[URISTR] eq NS_LS.'Selection';

	debug "  for $type_node->[URISTR]\n", 2;


 	# The class init_rev_subjs creates implicit subClassOf for
 	# second and nth stage super classes.  We only have to iterate
 	# through the subClassOf properties of the type.
 	#
 	foreach my $sc ( @{$type->arc_obj_list($subClassOf)} )
 	{
	    # Special handling of Resource. Added below
	    next if $sc->[NODE][URISTR] eq NS_RDFS.'Resource';

	    debug "    T $sc->[NODE][URISTR]\n", 2;

	    # These are SOLID, since they are dynamic
	    # TODO: Use the dynamic model
	    #
 	    $node->[TYPE]{$sc->[NODE][ID]}{$model_id} = 2;
	    $sc->[NODE][REV_TYPE]{$node->[ID]}{$model_id} = 2;
 	    # These types are dependent on the subClasOf statements
 	}
    }

    # Add RDFS:Resource, in case not done yet
    #
    $node->[TYPE]{&uri2id(NS_RDFS.'Resource')}{uri2id(NS_RDFS)} = 2;

    # The jumptable must be redone now!
    if( $node->[JUMPTABLE] )
    {
	debug "Resetting jumptable and DYNTABLE for ".
	  "$node->[URISTR]: $node->[JTK]\n", 1;
	$node->[JTK] = '--resetted--';
	undef $node->[JUMPTABLE];

	# Should we reset the dyntable? Yes!
	#
	undef $node->[DYNTABLE];
    }

    debug_end("declare_add_types", ' ', $self);
    return 1;
}

sub declare_add_prop
{
    my( $subj, $pred, $obj, $arc_uristr, $model, $solid ) = @_;

    $model ||= $subj->[WMODEL][NODE];
    $solid ||= 0;

    my $arc = $subj->declare_arc( $pred,
				  $subj,
				  $obj,
				  $arc_uristr,
				  $model,
				  $solid
				 );

    return $arc;
}

sub declare_arc
{
    my( $self, $pred, $subj, $obj, $uristr, $model, $solid ) = @_;

    # It *could* be that we have two diffrent arcs with the same URI,
    # if they comes from diffrent models.  The common case is that the
    # arcs with the same URI are identical.  The PRED, SUBJ, OBJ slots
    # are used for the common case.
    #
    # TODO: Use explicit properties if the models differs.
    #
    # All models says the same thing unless the properties are
    # explicit.

    # A defined [REV_SUBJ] only means that some props has been
    # defined. It doesn't mean that ALL props has been defined.

    # An existing prop key with an undef value means that we know that
    # the prop doesn't exist.  But a look for a nonexisting prop sould
    # (for now) trigger a complete initialization and set the complete
    # key.  If the prop key is defined, ALL the valus will be there.
    # (Maby we will change this to make position 0 in the list to hold
    # special data. Or maby change the value to be another hash.)

    # The concept of "complete list" depends on other selection.
    # Diffrent selections will have diffrent lists.  Every such
    # selection will be saved separately from the [REV_SUBJ] list.
    # It's existence guarantee that the list is complete.

    # TODO: Merge duplicate properties (with same obj or objs with
    # same value) frome same model !!!

    # TODO: Accept nodes as subj, pred, obj, and not only URIs,
    # scalars or contexts. The same for set_props()

    debug_start("declare_arc", ' ', $self);

    $subj = $self->get($subj) unless ref $subj;
    my $subj_node = $subj->[NODE];
    $model ||= $self->[WMODEL][NODE];
    $solid ||= 0;
    my $local = 0;

    # Checks for abbrevations
    $pred = $self->get_abbrev($pred) unless ref $pred;


    # handle special properties
    #
    # TODO: Support URIs for implicit properties
    #
    if( $pred->[NODE][URISTR] eq NS_RDF.'type' )
    {
	$subj->declare_add_types( [$obj], $model, $solid );

	debug_end("declare_arc", ' ', $self);
	return 1; # TODO: Return implicit uri for arc
    }


    if( ref $obj eq 'SCALAR' )
    {
	# TODO: Use static literal resources in some instances

	# The literal should by default be solid
	$obj = $self->declare_literal( $obj );

	$obj->[NODE][SOLID] = $solid;
	#
	# We should not have to do anything to REV_SUBJ_ALL, et
	# al, right?

	debug "Changing SOLID to $solid for $obj->[NODE][URISTR] ".
	  "IDS $obj->[NODE][IDS]\n", 3;
    }
    elsif( not ref $obj )
    {
	$obj = $self->get( $obj );
    }
    my $obj_node = $obj->[NODE];


    if( $DEBUG )
    {
	if( $obj_node->[VALUE] )
	{
	    unless( ref($obj_node->[VALUE]) eq 'SCALAR')
	    {
		confess "Bad value for $obj_node->[URISTR] ( ".
		  ref($obj_node->[VALUE])." ne 'SCALAR' )";
	    }
	}
    }


    if( $uristr )  # arc could be changed
    {
	# TODO: Check that tha agent owns the namespace
	# For now: Just allow models in the local namespace
	my $ns_l = NS_LD;
	unless( $uristr =~ /$ns_l/ )
	{
	    confess "Invalid namespace for literal: $uristr";
	}
	# TODO: Changing existing arc?
    }
    else  # The arc is created
    {
	# Checking for duplicates

	foreach my $arc ( @{$subj_node->[REV_SUBJ]{$pred->[NODE][ID]}} )
	{
	    if( $arc->[OBJ][ID] == $obj_node->[ID] and
		  $arc->[MODEL][ID] == $model->[ID] )
	    {
		if( $DEBUG >= 2 )
		{
		    debug "Duplicate arc in same model found:\n";
		    debug "   P $pred->[NODE][URISTR]\n";
		    debug "   S $subj_node->[URISTR]\n";
		    debug "   O $obj_node->[URISTR]\n";
		    debug "   M $model->[URISTR]\n";
		}
		debug_end("declare_arc", ' ', $self);
		return $self->new($arc);
	    }
	}



	# Who will know anything about this arc?  There could be
	# statements about it later, but not now.

	$uristr = NS_LD."arc/". &get_unique_id;
	$local = 1;

	# TODO: Call a miniversion of add_types that knows that no other
	# types has been added.  We should not require the setting of
	# types and props to initialize itself. The initialization
	# should be done here.
    }


    my $arc = $self->get( $uristr );
    my $arc_node = $arc->[NODE];

    $model or die "*** No WMODEL for arc $arc_node->[URISTR]\n";
    $arc_node->[IDS] or die "*** No IDS for arc $arc_node->[URISTR]\n";



    if( $DEBUG )
    {
	unless( ref( $model ) eq "RDF::Service::Resource" )
	{
	    confess "Bad model: $model";
	}

	debug "   P $pred->[NODE][URISTR]\n", 1;
	debug "   S $subj_node->[URISTR]\n", 1;
	debug "   O $obj_node->[URISTR]\n", 1;
	debug "   M $model->[URISTR]\n", 1;
	debug "   A $arc->[NODE][URISTR]\n", 1;
    }

    $arc_node->[PRED] = $pred->[NODE];
    $arc_node->[SUBJ] = $subj_node;
    $arc_node->[OBJ]  = $obj_node;
    $arc_node->[MODEL] = $model;
    $arc_node->[LOCAL] = $local;

    push @{ $subj_node->[REV_SUBJ]{$pred->[NODE][ID]} }, $arc_node;
    push @{ $obj_node->[REV_OBJ]{$pred->[NODE][ID]} }, $arc_node;
    push @{ $pred->[NODE][REV_PRED] }, $arc_node;
    $model->[REV_MODEL]{$arc_node->[ID]} = $arc_node;

    if( $solid )
    {
	debug "Changing SOLID to 1 for $arc_node->[URISTR] ".
	  "IDS $arc_node->[IDS]\n", 3;
	$arc_node->[SOLID] = 1;
    }
    else
    {
	debug "Changing SOLID to 0 for $arc_node->[URISTR] ".
	  "IDS $arc_node->[IDS]\n", 3;
	$arc_node->[SOLID] = 0;
	$subj_node->[REV_SUBJ_SOLID] = 0;
	$obj_node->[REV_OBJ_SOLID] = 0;
    }

    $arc->declare_add_types( [NS_RDF.'Statement'], NS_RDF, 1 );


    # TODO: Use creation triggers instead of checking all initialized
    # properties.

    # Since we added a new arc, there may be more dynamic arcs to be
    # added.  (And some dynamic arcs may have to be removed.)  This
    # goes for the subj, pred and obj.  Since an added property can
    # lead to more dynamic props and types, this arc could also expire
    # other resources dependent on the subj, pred and obj.  That's why
    # we emedietly have to find out if this changes the subj, pred or
    # obj.

    # TODO: Check for registred dependencies for expiering dynamic
    # properties and types.

    # TODO: For now, we just ignore the pred

    if( $subj_node->[TYPE_ALL] == 2 )
    {
	$subj_node->[TYPE_ALL] = 1;
	$subj->init_types;
    }


    # This will reconsider the dynamic props already initialized.
    # There may be more dynamic props with the same predicate
    #
    my $subj_subj_changed = 0;
    foreach my $pred_id ( grep { $subj_node->[REV_SUBJ_PREDS]{$_} == 2 }
			    keys %{$subj_node->[REV_SUBJ_PREDS]} )
    {
	$subj_node->[REV_SUBJ_PREDS]{$pred_id} = 1;
	$subj_subj_changed ++;
    }
    if( $subj_node->[REV_SUBJ_ALL] == 2 )
    {
	$subj_node->[REV_SUBJ_ALL] = 1;
	$subj_subj_changed ++;
    }
    $subj->init_rev_subjs if $subj_subj_changed;


    my $subj_obj_changed = 0;
    foreach my $pred_id ( grep { $subj_node->[REV_OBJ_PREDS]{$_} == 2 }
			    keys %{$subj_node->[REV_OBJ_PREDS]} )
    {
	$subj_node->[REV_OBJ_PREDS]{$pred_id} = 1;
	$subj_obj_changed ++;
    }
    if( $subj_node->[REV_OBJ_ALL] == 2 )
    {
	$subj_node->[REV_OBJ_ALL] = 1;
	$subj_obj_changed ++;
    }
    $subj->init_rev_objs if $subj_obj_changed;



    if( $obj_node->[TYPE_ALL] == 2 )
    {
	$obj_node->[TYPE_ALL] = 1;
	$obj->init_types;
    }

    my $obj_subj_changed = 0;
    foreach my $pred_id ( grep { $obj_node->[REV_SUBJ_PREDS]{$_} == 2 }
			    keys %{$obj_node->[REV_SUBJ_PREDS]} )
    {
	$obj_node->[REV_SUBJ_PREDS]{$pred_id} = 1;
	$obj_subj_changed ++;
    }
    if( $obj_node->[REV_SUBJ_ALL] == 2 )
    {
	$obj_node->[REV_SUBJ_ALL] = 1;
	$obj_subj_changed ++;
    }
    $obj->init_rev_subjs if $obj_subj_changed;


    my $obj_obj_changed = 0;
    foreach my $pred_id ( grep { $obj_node->[REV_OBJ_PREDS]{$_} == 2 }
			    keys %{$obj_node->[REV_OBJ_PREDS]} )
    {
	$obj_node->[REV_OBJ_PREDS]{$pred_id} = 1;
	$obj_obj_changed ++;
    }
    if( $obj_node->[REV_OBJ_ALL] == 2 )
    {
	$obj_node->[REV_OBJ_ALL] = 1;
	$obj_obj_changed ++;
    }
    $obj->init_rev_objs if $obj_obj_changed;


    debug_end("declare_arc", ' ', $self);
    return $arc;
}





1;


__END__
