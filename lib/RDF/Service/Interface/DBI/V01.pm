#  $Id: V01.pm,v 1.40 2001/04/11 16:51:21 aigan Exp $  -*-cperl-*-

package RDF::Service::Interface::DBI::V01;

#=====================================================================
#
# DESCRIPTION
#   Interface to storage and retrieval of statements in a general purpouse DB
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
use DBI;
#use POSIX;
#use Time::HiRes qw( time );
use vars qw( $prefix $interface_uri @node_fields );
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( get_unique_id uri2id id2uri debug $DEBUG );
use RDF::Service::Resource;
use Data::Dumper;
use Carp;


# TODO: Database optimization.  PostgreSQL does a sync() after each DB
# write for maximal protection against database corruption.  Remove
# this sync() to speed up database interaction!



$prefix = [ ];

# Todo: Decide on a standard way to name functions
# # Will not use the long names in this version...
$interface_uri = "org.cpan.RDF.Interface.DBI.V01";

@node_fields = qw( id uri iscontainer isprefix
	     label aliasfor
	     pred distr subj obj model
	     member
	     isliteral lang value );


sub register
{
    my( $i, $args ) = @_;

    my $connect = $args->{'connect'} or croak "Connection string missing";
    my $name    = $args->{'name'} || "";
    my $passwd  = $args->{'passwd'} || "";

    my $dbi_options =
    {
	RaiseError => 0,
    };

    my $dbh = ( DBI->connect_cached( $connect, $name, $passwd, $dbi_options ) );


    die "Connect to $connect failed\n" unless $dbh;

    # Maby we should store interface data in a special hash instead,
    # like interface($interface->[ID])->{'dbh'}... But that seams to
    # be just as long.  Another alternative would be to reserve a
    # range especially for interfaces.
    #
    #
    # This interface module can be used for connection to several
    # diffrent DBs.  Every such connection will have the same methods
    # but the method calls will give diffrent results.  It is diffrent
    # interface objects but the same interface module.
    #
    debug "Store DBH for $i->[URISTR] in ".
	"[PRIVATE]{$i->[ID]}{'dbh'}\n", 3;

    $i->[PRIVATE]{$i->[ID]}{'dbh'} = $dbh;

    return
    {
	'' =>
	{
	    'methods' =>
	    {
		NS_LS.'Model' =>
		{
		    # 'add_arc'        => [\&add_arc],
		    # 'find_arcs_list' => [\&find_arcs_list],
		},
		NS_RDFS.'Resource'   =>
		{
		    'init_src_types'     => [\&init_types],
		    'init_src_rev_subjs' => [\&init_rev_subjs],
		    'init_src_rev_objs'  => [\&init_rev_objs],
		    'init_src_rev_preds' => [\&init_rev_preds],
		    'find_node'          => [\&find_node],
		    'store_types'        => [\&store_types],
		    'store_props'        => [\&store_props],
		    'store_node'         => [\&store_node],
		    'remove'             => [\&remove],
		    'remove_types'       => [\&remove_types],
		    'remove_props'       => [\&remove_props],
		},
		NS_RDFS.'Class' =>
		{
		    'init_src_rev_types' => [\&init_rev_types],
		},
	    },
	},
    };
}



sub find_node
{
    my( $self, $i, $uristr ) = @_;
    #
    # Is the node contained in the model?

    my $p = {}; # Interface private data
    my $obj;

    # Look for the URI in the DB.
    #
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
              select id, refid, refpart, hasalias from uri
              where string=?
              ");
    $sth->execute( $uristr );

    my( $r_id, $r_refid, $r_refpart, $r_hasalias );
    $sth->bind_columns(\$r_id, \$r_refid, \$r_refpart, \$r_hasalias);
    if( $sth->fetch )
    {
	$p->{'uri'} = $r_id;

	$obj = $self->get( $uristr );
	$obj->[NODE][PRIVATE]{$i->[ID]} = $p;
    }
    $sth->finish; # Release the handler

    return( $obj, 1 ) if defined $obj;
    return( undef, 0 );
}

sub name
{
    # Will give the part of the URI following the 'namespace'
    die "not implemented";
}

sub init_rev_subjs
{
    my( $self, $i, $constraint ) = @_;

    # This should initiate all props from this interface

    return(1,3) if $self->[NODE][REV_SUBJ_I]{$i->[ID]}{'ALL'};

    # TODO: Use the constraint

    # TODO: interface private data registrers fetched properties, with
    # one dependency callback in the expire slot for each arc.


    $self->[NODE][TYPE_ALL] == 2 or $self->init_types;

    # TODO: Should props be undef if type changes?

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $p = $self->[NODE][PRIVATE]{$i->[ID]} || {};

    # TODO: Also read all the other node data

    my $sth = $dbh->prepare_cached("
              select auri.string as arc,
                     puri.string as pred,
                     suri.string as subj,
                     ouri.string as obj,
                     muri.string as model
              from node,
                   uri auri,
                   uri puri,
                   uri suri,
                   uri ouri,
                   uri muri
              where node.pred  = puri.id and
                    node.subj  = suri.id and
                    node.obj   = ouri.id and
                    node.model = muri.id and
                    node.uri   = auri.id and
                    suri.string = ?
              ");

    $sth->execute( $self->[NODE][URISTR] );
    my $tbl = $sth->fetchall_arrayref({});
    $sth->finish;

    debug "Fetching props\n", 1;
    foreach my $r ( @$tbl )
    {
	my $pred   = $self->get( $r->{'pred'} );
	my $subj   = $self;
	my $obj    = $self->get( $r->{'obj'} );
	my $model  = $self->get( $r->{'model'} )->[NODE];
	debug "..Found a $pred->[NODE][URISTR]\n", 1;

	# TODO:  Do not add a prop if that prop already is initialized!
	#
	$subj->declare_add_prop( $pred, $obj, $r->{'arc'}, $model, 1 );
    }

    # All preds is initiated
    # TODO: Unless we only fetch some of the preds
    #
    $self->[NODE][REV_SUBJ_I]{$i->[ID]}{'ALL'} = 1;

    return( 1, 3 );
}

sub init_rev_objs
{
    my( $self, $i, $constraint ) = @_;

    return(1,3) if $self->[NODE][REV_OBJ_I]{$i->[ID]}{'ALL'};

    # This should get all rev_props from this interface
    # TODO: Use the constraint

    $self->[NODE][TYPE_ALL] == 2 or $self->init_types;

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $p = $self->[NODE][PRIVATE]{$i->[ID]} || {};

    # TODO: Also read all the other node data

    my $sth = $dbh->prepare_cached("
              select auri.string as arc,
                     puri.string as pred,
                     suri.string as subj,
                     ouri.string as obj,
                     muri.string as model
              from node,
                   uri auri,
                   uri puri,
                   uri suri,
                   uri ouri,
                   uri muri
              where node.pred  = puri.id and
                    node.subj  = suri.id and
                    node.obj   = ouri.id and
                    node.model = muri.id and
                    node.uri   = auri.id and
                    ouri.string = ?
              ");

#    warn "*** $self->[NODE][URISTR]\n";

    $sth->execute( $self->[NODE][URISTR] );
    my $tbl = $sth->fetchall_arrayref({});
    $sth->finish;

    debug "Fetching rev_props\n", 1;
    foreach my $r ( @$tbl )
    {
	my $pred   = $self->get( $r->{'pred'} );
	my $subj   = $self->get( $r->{'subj'} );
	my $obj    = $self;
	my $model  = $self->get( $r->{'model'} )->[NODE];
	debug "..Found a $pred->[NODE][URISTR]\n", 1;

	unless( $subj->[NODE][REV_SUBJ]{$pred->[NODE][ID]} )
	{
	    $subj->init_rev_subjs( [$pred->[NODE]] );
	}
    }

    $self->[NODE][REV_OBJ_I]{$i->[ID]}{'ALL'} = 1;

    return( 1, 3 );
}

sub init_rev_preds
{
    my( $self, $i, $constraint ) = @_;

    # This should get all rev_preds from this interface


    # TODO: Use the constraint


    $self->[NODE][TYPE_ALL] == 2 or $self->init_types;

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $p = $self->[NODE][PRIVATE]{$i->[ID]} || {};

    # TODO: Also read all the other node data

    my $sth = $dbh->prepare_cached("
              select auri.string as arc,
                     puri.string as pred,
                     suri.string as subj,
                     ouri.string as obj,
                     muri.string as model
              from node,
                   uri auri,
                   uri puri,
                   uri suri,
                   uri ouri,
                   uri muri
              where node.pred  = puri.id and
                    node.subj  = suri.id and
                    node.obj   = ouri.id and
                    node.model = muri.id and
                    node.uri   = auri.id and
                    puri.string = ?
              ");

#    warn "*** $self->[NODE][URISTR]\n";

    $sth->execute( $self->[NODE][URISTR] );
    my $tbl = $sth->fetchall_arrayref({});
    $sth->finish;

    debug "Fetching rev_preds\n", 1;
    foreach my $r ( @$tbl )
    {
	my $pred   = $self;
	my $subj   = $self->get( $r->{'subj'} );
	my $obj    = $self->get( $r->{'obj'} );
	my $model  = $self->get( $r->{'model'} )->[NODE];
	debug "..Found a $pred->[NODE][URISTR]\n", 1;

	unless( $subj->[NODE][REV_SUBJ]{$pred->[NODE][ID]} )
	{
	    $subj->init_rev_subjs( [$pred->[NODE]] );
	}
    }

    return( 1, 3 );
}

sub init_types
{
    my( $self, $i ) = @_;
    #
    # Read the types from the DBI.  Get all info from the node
    # record

    # TODO: Do not call the database for the types if they already has
    # been read.  ...

    # TODO: Get the implicite types from subClassOf (Handled by
    # Base/V01)

    if( $DEBUG )
    {
	debug "Init types for $self->[NODE][URISTR]\n", 2;

	unless( ref $self eq "RDF::Service::Context" )
	{
	    die "Wrong type for self: $self";
	}

	unless( ref $i eq "RDF::Service::Resource" )
	{
	    die "Wrong type for i: $i";
	}

	die "No node for self" unless $self->[NODE];

	die "No private for self_node" unless $self->[NODE][PRIVATE];
    }

    # Look for the URI in the DB.
    #
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my $p = $self->[NODE][PRIVATE]{$i->[ID]} || {};
    $p->{'uri'} ||= &_get_id($self->[NODE], $i);

    my $node = $self->[NODE];

  Node:
    {
	# TODO: Reuse cols variable and sth
	my @cols = qw( id iscontainer isprefix label aliasfor
		       model pred distr subj obj member isliteral
		       lang value blob );

	my $fields = join ", ", @cols;

	my $sth_node = $dbh->prepare_cached("
              select $fields
              from node
              where uri=?
              ");

	my $true = '1';
	my  $false = '0';

	$sth_node->execute( $p->{'uri'} );
	my $tbl = $sth_node->fetchall_arrayref({});
	$sth_node->finish; # The fetchall should finish the sth implicitly

	# TODO: Handle the case with more than one hit!

	foreach my $r ( @$tbl )
	{
	    debug "Changing SOLID to 1 for $node->[URISTR] ".
	      "IDS $node->[IDS]\n", 3;
	    $node->[SOLID] = 1; # Resource found in db
	    my $types = [];

	    # TODO: Go through all the varables

	    # iscontainer

	    # isprefix

	    # aliasfor

	    # model
	    my $model_res = &_get_node($r->{'model'}, $self, $i);
	    my $model = $model_res->[NODE];
	    $node->[MODEL] = $model;
	    $model->[REV_MODEL]{$node->[ID]} = $node;
	    if( $DEBUG )
	    {
		unless( $model_res->could_be_a( NS_LS.'Model' ) )
		{
		    die "The model is not a model";
		}
	    }

	    # label
	    if( my $label = $r->{'label'} )
	    {
		# Copy label, because we send a scalar ref!
		# Set property as solid!
		$self->declare_add_prop( NS_RDFS.'label', \$label,
					 undef, $model, 1 );
	    }

	    # pred distr subj obj
	    if( my $r_pred = $r->{'pred'} )
	    {
		push @$types, NS_RDF.'Statement';
	    }

	    # member

	    # isliteral, lang, value, blob
	    if( $r->{'isliteral'} eq $true )
	    {
		debug "..Literal: $self->[NODE][URISTR]\n", 2;
		if( $r->{'value'} )
		{
		    # Rewrite from $r->{'value'}
		    $self->[NODE][VALUE] = \${$r}{'value'};
		    push @$types, NS_RDFS.'Literal';

		    if( $DEBUG )
		    {
			unless( ref $self->[NODE][VALUE] eq 'SCALAR' )
			{
			    die "Value not a string ( $self->[NODE][VALUE] ) ";
			}
		    }
		}
		else
		{
		    die "not implemented";
		}
	    }
	    $self->declare_add_types( $types, $model, 1 );
	}
    }


  Types:
    {
	my $sth_types = $dbh->prepare_cached("
              select type.id, string, type, model
              from type, uri
              where node=? and uri.id=type
              ");

	$sth_types->execute( $p->{'uri'} );
	my $tbl = $sth_types->fetchall_arrayref({});
	$sth_types->finish;
	foreach my $r ( @$tbl )
	{
	    my $type = $self->get($r->{'string'});
	    my $model = &_get_node( $r->{'model'}, $self, $i )->[NODE];

	    # Remember the record ID
	    $type->[NODE][PRIVATE]{$i->[ID]}{'uri'} = $r->{'type'};

	    # TODO: Maby group the types before creating them
	    $self->declare_add_types( [$type], $model, 1 );
	}
    }

    debug "Types for $self->[NODE][URISTR]\n", 1;
    debug $self->types_as_string, 1;

    return( 1, 3 );
}

sub init_rev_types
{
    my( $self, $i ) = @_;
    #
    # Read the types from the DBI.

    # TODO: Get the implicite types from subClassOf. ( Should be
    # handled by declare_add_rev_types )

    # I may the assumption that this initiation does not affect
    # knowledge of the resource SOLID state.


    # Look for the URI in the DB.
    #
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my $p = $self->[NODE][PRIVATE]{$i->[ID]} || {};
    $p->{'uri'} ||= &_get_id($self->[NODE], $i);

    my $rev_types = [];

    my $sth_rev_types = $dbh->prepare_cached("
              select type.id, string, node, model
              from type, uri
              where type=? and uri.id=node
              ");

    $sth_rev_types->execute( $p->{'uri'} );
    my $tbl = $sth_rev_types->fetchall_arrayref({});
    $sth_rev_types->finish;
    foreach my $r ( @$tbl )
    {
	my $rev_type = $self->get($r->{'string'});
	my $model = &_get_node( $r->{'model'}, $self, $i )->[NODE];

	# Remember the record ID
	$rev_type->[NODE][PRIVATE]{$i->[ID]}{'uri'} = $r->{'node'};

	# By initiate the types of this object, it will also registrer
	# istself as having this class as type, and by that also
	# registring a rev_type in this class.
	#
	$rev_type->[NODE][TYPE_ALL] == 2 or $rev_type->init_types;

	# TODO: Replace the above with something like this, in order
	# to not make a complete type initialization for each member
	# of a class
	#
	#	$rev_type->declare_add_types( [$self], $model, 1 );
    }

    return( 1, 3 );
}


sub remove
{
    my( $self, $i ) = @_;

    # Remove node from interface. But not from the cahce.  This is
    # called from Base delete before it removes the node from cache.

    # TODO: Check that the node (with the model) actually exist in
    # this interface

    # Handle special properties

    # TODO: If this is a label arc, remove the label from subj by
    # updating the node.  As a bonus, check if we can remove the
    # sybject node entierly


    # Remove types and node

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $sth_type = $dbh->prepare_cached("
                    delete from type
                    where node = ? and model = ?");
    my $sth_node = $dbh->prepare_cached("
                    delete from node
                    where uri = ? and model = ?");

    my $r_model = &_get_id( $self->[WMODEL][NODE], $i );
    my $r_node  = &_get_id( $self->[NODE],  $i );
    my $node_p = $self->[NODE][PRIVATE]{$i->[ID]} || {};

    $sth_type->execute( $r_node, $r_model)
      or confess( $sth_type->errstr );
    $sth_node->execute( $r_node, $r_model)
      or confess( $sth_type->errstr );

    debug "Deleted $self->[NODE][URISTR] for model ".
      $self->[WMODEL][NODE][URISTR]."\n", 1;

    # Remove the private information.  This removes info for all
    # models.  Not just the deleted one.

    # TODO: Check that there is no mixup between diffrent models
    # interface private data in the same node.

    delete $self->[NODE][PRIVATE]{$i->[ID]};

    # TODO: What happens if the resource is stored in several
    # interfaces?  When should we set SOLID to false?

    return( 1, 3 );
}

sub store_types
{
    my( $self, $i ) = @_;
    #
    # TODO: Could store duplicate type statements. But only from
    # diffrent models.

    my $node = $self->[NODE];

    debug $self->types_as_string, 2;


    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my $p = $node->[PRIVATE]{$i->[ID]} || {};

    my $sth = $dbh->prepare_cached("
                   insert into type
                   (node, type, model)
                   values (?, ?, ?)
    ");

    my $r_node  = &_get_id($node, $i);

    foreach my $type_id ( keys %{$node->[TYPE]} )
    {
	my $type = $self->get_context_by_id( $type_id );
	my $r_type = &_get_id($type->[NODE], $i);

	debug "..Checking $type->[NODE][URISTR]\n", 2;

	$type->store; # Store the type if necessary

	foreach my $model_id ( keys %{$node->[TYPE]{$type_id}} )
	{
	    # TODO: Use _get_id_by_node_id
	    my $model = $self->get_context_by_id( $model_id )->[NODE];
	    debug "....Model $model->[URISTR]\n", 2;

	    # Don't store type if it's already solid
	    if( $node->[TYPE]{$type_id}{$model_id} == 2 )
	    {
		my $uri = &id2uri( $type_id );
		debug "      Already solid: $uri\n", 1;
		next;
	    }

	    debug "      Saving type in DB\n", 2;

	    my $r_model = &_get_id($model, $i);
	    $sth->execute( $r_node, $r_type, $r_model )
	      or confess( $sth->errstr );

	    # Type is now solid!
	    $node->[TYPE]{$type_id}{$model_id} = 2;
	}
    }

    # This interface store all the types. Do not continue
    return( 1, 1 );
}

sub remove_types
{
    my( $self, $i, $types, $model ) = @_;

    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
                   delete from type
                   where node=? and type=? and model=?
    ");

    $model ||= $self->[WMODEL][NODE];
    my $r_node  = &_get_id($self->[NODE], $i);
    my $r_model = &_get_id($model, $i);

    foreach my $type ( @$types )
    {
	debug "  t $type->[NODE][URISTR]\n", 2;

	my $r_type = &_get_id($type->[NODE], $i);
	$sth->execute( $r_node, $r_type, $r_model )
	    or confess( $sth->errstr );
    }

    return( 1, 3 );
}

sub store_props
{
    my( $self, $i ) = @_;
    #
    # Stores non-SOLID props. Implicit preds should not be included in
    # the $preds list.  Preds already stored must be SOLID.

    # TODO; This strategy of checking all mentioned things for if it
    # should be stored, will result in the whole trea being
    # initialized.  If its not yet initialized, it will read
    # practically everything.  Maby that's not so smart?

    my $node = $self->[NODE];

    foreach my $pred_id ( keys %{$node->[REV_SUBJ]} )
    {
	my $pred = $self->get_context_by_id($pred_id);
	$pred->store; # Store the pred if necessary

	foreach my $arc_node ( @{$node->[REV_SUBJ]{$pred_id}} )
	{
	    $self->new($arc_node)->store;
	    $self->new($arc_node->[OBJ])->store;
	}
    }

    # This interface store all the props. Do not continue
    return( 1, 1 );
}


sub store_node
{
    my( $self, $i ) = @_;
    #
    # Store the object in the database

    my $node = $self->[NODE];

    # TODO: Hanle MULTI

    # Should we update, create or ignore the node?
    #
    # TODO: Handle other special data
    #
    if( $node->[PRED] )
    {
	# Special properties
	#
	if( $node->[PRED][URISTR] eq NS_RDFS.'label' )
	{
	    my $subj = $self->new($node->[SUBJ]);
	    $subj->[NODE][SOLID] = 0;
	    debug "Changing SOLID to 0 for $subj->[NODE][URISTR] ".
		  "IDS $subj->[NODE][IDS]\n", 3;
	    $subj->store;
	    return(1,1);
	}
    }


    # Is there anything in the node to store?
    #
    if( $node->[PRED] or $node->[VALUE] or
	  $node->[MEMBER] or $self->arc_obj_value( NS_RDFS.'label' )
	 )
    {
	my $p = $node->[PRIVATE]{$i->[ID]} || {};
	my $node_exist = $p->{'id'};
	unless( $node_exist )
	{
	    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
	    my $sth = $dbh->prepare_cached("
              select id
              from node
              where uri=?
              ");
	    $p->{'uri'} ||= &_get_id($self->[NODE], $i);
	    $sth->execute( $p->{'uri'} );
	    $node_exist = 1 if $sth->rows;
	    $sth->finish;
	}

	if( $node_exist )
	{
	    &_update_node($self, $i);
	}
	else
	{
	    &_create_node($self, $i);
	}
    }
    else
    {
	debug "..The node is neither Literal nor arc!\n", 4;
    }

    # The resource is now stored and SOLID
    #
    debug "Changing SOLID to 1 for $node->[URISTR] ".
      "IDS $node->[IDS]\n", 3;
    $node->[SOLID] = 1;

    return( 1, 1);
}

sub _update_node
{
    my( $self, $i ) = @_;
    # This only updates the node; not the types or properties.  Mainly
    # used to update literals

    # TODO: What shall we do about multipple models?

    my $node = $self->[NODE];

    my $p = $self->[NODE][PRIVATE]{$i->[ID]} || {};
    my %p = %$p;
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};


    # TODO: Only do this the first time
    #
    my $field_str = join ", ", map "$_=?",
      @node_fields[1..$#node_fields];

    my $sth = $dbh->prepare_cached(" update node
                                    set $field_str
                                    where uri = ?
                                    and model = ?
                                   ");

    $p{'uri'}         ||= &_get_id( $self->[NODE], $i) or die;
    $p{'iscontainer'} = 'false';
    $p{'isprefix'}    = 'false';
    $p{'aliasfor'}    ||= &_get_id( $self->[NODE][ALIASFOR], $i);

    $p{'pred'}        ||= &_get_id( $self->[NODE][PRED], $i);
    $p{'distr'}       = 'false';
    $p{'subj'}        ||= &_get_id( $self->[NODE][SUBJ], $i);
    $p{'obj'}         ||= &_get_id( $self->[NODE][OBJ], $i);


    # TODO: What should the new model be?
    $p{'model'}       ||= &_get_id( $self->[WMODEL][NODE], $i) or die;

    $p{'member'}      ||= &_get_id( $self->[NODE][MEMBER], $i);


    # Special properties
    #
    $p{'label'}       = undef;
    # TODO: Use arc_list ?
    if( my $arc = $self->arc(NS_RDFS.'label')->list->[0] )
    {
	$arc->[NODE][SOLID] = 1;
	$p{'label'}   = ${ $arc->[NODE][OBJ][VALUE] };
	$arc->[NODE][OBJ][SOLID] = 1;
    }




    # TODO: Use isa(literal)
    if( $self->[NODE][VALUE] )
    {
	if( $DEBUG )
	{
	    ref $self->[NODE][VALUE] eq 'SCALAR' or
	      die "Value not a string";
	}

	$p{'isliteral'}   = 'true';
	$p{'lang'}        = undef;
	if( length(${$self->[NODE][VALUE]}) <= 250 )
	{
	    $p{'value'}       = ${$self->[NODE][VALUE]};
	}
	else
	{
	    die "not implemented";
	}
    }
    else
    {
	$p{'isliteral'}   = 'false';
    }


    debug "Updating value to ($p{'value'})\n", 2;
    debug ".. where uri=$p{'uri'} and model=$p{'model'}\n", 2;


    $sth->execute( map $p{$_}, @node_fields[1..$#node_fields],
		   'uri', 'model' )
	or confess( $sth->errstr );

    $self->[NODE][PRIVATE]{$i->[ID]} = \%p;

    return;
}

sub _create_node
{
    my( $self, $i ) = @_;
    #
    # Stores the object in the database.  The object does not exist
    # before this. All data gets stored in the supplied $model.

    debug "_create_node $self->[NODE][URISTR]\n", 2;

    my $model = $self->[WMODEL][NODE];
    my $node = $self->[NODE];

    # Interface PRIVATE data. These has to be updated then the
    # corresponding official data change. The dependencies could be
    # handled as they are (will be) in RDF::Cache
    #
    my $p = $node->[PRIVATE]{$i->[ID]} || {};
    my %p = %$p;

    debug "Getting DBH for $i->[URISTR] from ".
	"[PRIVATE]{$i->[ID]}{'dbh'}\n", 3;
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};


    # TODO: Only do this the first time
    #
    my $field_str = join ", ", @node_fields;
    my $place_str = join ", ", ('?')x @node_fields;

    my $sth = $dbh->prepare_cached("  insert into node
				      ($field_str)
				      values ($place_str)
				      ");

    # This is a new node. We know that it doesn't exist yet. Create a
    # new record in the db
    #
    $p{'id'}     ||= &_nextval($dbh) or die;

    # TODO: method calls should be used, i case the attribute hasn't
    # been initialized. $self->pred->private($i, 'id')?  It's possible
    # that the attribute object is stored in several interfaces. We
    # are only intrested in the private id for this interface. We
    # can't make a special method for getting that id, because we
    # can't guarantee that another interface doesn't have the same
    # method.  The private() method could be constructed to access a
    # specific attribute, but that doesn't seem to be much better than
    # just using the _get_id() function.
    #
    # I don't like this repetivity there we get the
    # sth and execute it once for each resource.  How much can we save
    # by group the lookups together?
    #
    # The list below could be shortend if we knew the type of node to
    # create.
    #
    $p{'uri'}         ||= &_create_uri( $node->[URISTR], $i) or die;
    $p{'iscontainer'} = 'false';
    $p{'isprefix'}    = 'false';
    $p{'aliasfor'}    ||= &_get_id( $node->[ALIASFOR], $i);
    $p{'pred'}        ||= &_get_id( $node->[PRED], $i);
    $p{'distr'}       = 'false';
    $p{'subj'}        ||= &_get_id( $node->[SUBJ], $i);
    $p{'obj'}         ||= &_get_id( $node->[OBJ], $i);
    $p{'model'}       ||= &_get_id( $model, $i) or die;
    $p{'member'}      ||= &_get_id( $node->[MEMBER], $i);

    # Special properties
    #
    $p{'label'}       = undef;
    # TODO: Use arc_list ?
    if( my $arc = $self->arc(NS_RDFS.'label')->list->[0] )
    {
	$arc->[NODE][SOLID] = 1;
	$p{'label'}   = ${ $arc->[NODE][OBJ][VALUE] };
	$arc->[NODE][OBJ][SOLID] = 1;
    }



    if( $node->[VALUE] )
    {
	if( $DEBUG )
	{
	    ref $node->[VALUE] eq 'SCALAR' or
	      die "Value not a string: ( $node->[VALUE] )";
	}

	$p{'isliteral'}   = 'true';
	$p{'lang'}        = undef;
	if( length(${$node->[VALUE]}) <= 250 )
	{
	    $p{'value'}       = ${$node->[VALUE]};
	}
	else
	{
	    die "not implemented";
	}
    }
    else
    {
	$p{'isliteral'}   = 'false';
    }

    debug ".. id: $p{'id'}\n", 1;
    debug "..uri: $p{'uri'}\n", 1;

#    confess "SQL insert node $node->[URISTR]\n" if $DEBUG;

    $node->[PRIVATE]{$i->[ID]} = \%p;

    $sth->execute( map $p{$_}, @node_fields )
	or confess( $sth->errstr );

    return;
}

sub _get_node
{
    my( $r_id, $caller, $i ) = @_;
    #
    # find_node_by_interface_node_id


    # TODO: Optimize with a interface id cache

    # Look for the URI in the DB.
    #
    my $dbh = $i->[PRIVATE]{$i->[ID]}{'dbh'};
    my $p = {}; # Interface private data
    my $obj;
    $p->{'id'} = $r_id;

    my $sth = $dbh->prepare_cached("
              select string, refid, refpart, hasalias from uri
              where id=?
              ");
    $sth->execute( $r_id );

    my( $r_uristr, $r_refid, $r_refpart, $r_hasalias );
    $sth->bind_columns(\$r_uristr, \$r_refid, \$r_refpart, \$r_hasalias);
    if( $sth->fetch )
    {
	$obj = $caller->get( $r_uristr );
	$obj->[NODE][PRIVATE]{$i->[ID]} = $p;
    }
    $sth->finish; # Release the handler

    die "couldn't find the resource with record id $r_id" unless $obj;

    return $obj;
}

sub _get_id
{
    return undef unless defined $_[0]; # Common case
    my( $obj_node, $interface ) = @_;
    #
    # The object already exist.  Here we just want to know what id it
    # has in the DB. NB!!! field URI in NODE table.


    debug "***** _get_id !!!\n", 2;

    if( $DEBUG )
    {
	debug "_get_id( $obj_node->[URISTR] )\n", 2;
	unless( ref $obj_node eq "RDF::Service::Resource" )
	{
	    confess "obj_node $obj_node malformed ";
	}
    }

    # Has the object a known connection to the DB?
    #
    my $p = $obj_node->[PRIVATE]{$interface->[ID]} || {};
    if( defined( my $id = $p->{'uri'}) )
    {
	return $id;
    }


    $obj_node->[URISTR] or die "No URI supplied";

    # Look for the URI in the DB.
    #
    my $dbh = $interface->[PRIVATE]{$interface->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
              select id, refid, refpart, hasalias from uri
              where string=?
              ");
    $sth->execute( $obj_node->[URISTR] );

    my( $r_id, $r_refid, $r_refpart, $r_hasalias );
    $sth->bind_columns(\$r_id, \$r_refid, \$r_refpart, \$r_hasalias);
    if( $sth->fetch )
    {
	$p->{'uri'} = $r_id;
	$sth->finish; # Release the handler

	# TODO: Maby update other data with the result?
	return $r_id;
    }
    else
    {
	$sth->finish; # Release the handler

	# If URI not found in DB:
	#
	# Insert the uri in the DB. The object itself doesn't have to be
	# inserted since it would already be in the DB if this interface
	# handles its storage.

	$p->{'uri'} = &_create_uri( $obj_node->[URISTR], $interface );
	$obj_node->[PRIVATE]{$interface->[ID]} = $p;
	return $p->{'uri'};
    }
}

sub _create_uri
{
    my( $uri, $interface ) = @_;
    #
    # Insert a new URI in the DB.

    debug "_create_uri( $uri )\n", 2;

    # Same as _get_id(), except that we know that the uri doesn't
    # exist in the db. No error checking.

    my $dbh = $interface->[PRIVATE]{$interface->[ID]}{'dbh'};

    my $sth = $dbh->prepare_cached("
                  insert into uri
                  (string, id, hasalias)
                  values (?,?,false)
                  ");
    my $id = &_nextval($dbh, 'uri_id_seq');
    $sth->execute($uri, $id);
    die unless defined $id;

    return $id;
}

sub _nextval
{
    my( $dbh, $seq ) = @_;

    # Values could be collected before they are needed, as to save the
    # lookup time.

    $seq ||= 'node_id_seq';
    my $sth = $dbh->prepare_cached( "select nextval(?)" );
    $sth->execute( $seq );
    my( $id ) = $sth->fetchrow_array;
    $sth->finish;

    $id or die "Failed to get nextval";
}

1;
