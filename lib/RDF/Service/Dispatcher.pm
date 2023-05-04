#  $Id: Dispatcher.pm,v 1.32 2001/04/03 14:18:20 aigan Exp $  -*-perl-*-

package RDF::Service::Dispatcher;

#=====================================================================
#
# DESCRIPTION
#   Forwards Resource actions to the appropriate interface
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
use base 'Exporter';
use vars qw( %JumpJumpTable %JumpPropTable @EXPORT_OK %EXPORT_TAGS );
use RDF::Service::Constants qw( :all );
use RDF::Service::Cache qw( interfaces uri2id debug $DEBUG
			  debug_start debug_end ); #);
use Data::Dumper;
use Carp;

# Every resource can only belong to one dispatcher. This should change
# in a future version.

{

    @EXPORT_OK = qw( go create_jumptable select_jumptable
    %JumpJumpTable %JumpPropTable );

}

sub go
{
    my( $self, $call, @args ) = @_;

    my $node = $self->[NODE];
#    @args ||= ();

    debug "--( call $call )\n", 3;

    if( $DEBUG )
    {
	unless( ref( $self ) eq 'RDF::Service::Context' )
	{
	    confess "Called with invalid object: $self";
	}
	if( $node->[MODEL] )
	{
	    ref $node->[MODEL] eq 'RDF::Service::Resource'
	      or confess "Bad model ($node->[MODEL])";
	}
	if( $node->[VALUE] )
	{
	    unless( ref( $node->[VALUE]) eq 'SCALAR')
	    {
		confess "Bad value for $node->[URISTR] ( ".
		  ref($node->[VALUE])." ne 'SCALAR' )";
	    }
	}
	unless( length( $node->[IDS] ) )
	{
	    confess "No IDS" if $node->[RUNLEVEL];
	}
	unless( ref($self->[HISTORY]) eq 'ARRAY' )
	{
	    confess "Malformed HISTORY: $self->[HISTORY]";
	}
	unless( $node->[URISTR] =~ /^(http|value):/ )
	{
	    confess "That's not an URI ($node->[URISTR]).  ".
	      "Well. It could be, but probably not";
	}
	$node->[URISTR] or
	  confess "Call to $call from anonymous obj";
    }


    # Todo: optimize for common case
    if( not defined $node->[JUMPTABLE] )
    {
	&select_jumptable( $self );
    }



    ### Dispatch to the handling interfaces
    ###

    if( defined(my $coderef = $node->[JUMPTABLE]{$call}) )
    {
	# TODO: If call not found: treat this as a property and maby
	# as an dynamic property


	# Also used in init_rev_subjs() for DYNTABLE calls
	#

	my $call_key = "$call $self->[NODE] ".
	  ( join ' ', map defined $_ ? $_:"", @args );
	foreach( @{$self->[HISTORY]} )
	{
	    if( $_ eq $call_key )
	    {
		debug "Recursive call '$call_key' skipped", 2;
		return 0;
	    }
	}
#	warn "---<<< called $call_key >>>---\n";
	push @{$self->[HISTORY]}, $call_key;


	debug "Dispatching $call...\n", 2;

	# Return a object or a list ref.
	#  Arg 1: the return value
	#  Arg 2: Action
	#         0     = Ignore this result; call next
	#         1     = Final; Return result
	#         2     = Part; Append and call next
	#         3     = Successful. Call next. Return 1

	my $success = 0;
	my $result = [];
	my $result_type = 0;

	for( my $i=0; $i<= $#$coderef; $i++ )
	{
	    next if $result_type == 1;

	    debug_start( $call, $i, $self );
	    debug "..Calling $coderef->[$i][1][URISTR]\n", 2;

	    # The second parameter is the interface object
	    my( $res, $action ) = &{$coderef->[$i][0]}($self,
						       $coderef->[$i][1],
						       @args);

	    if( not defined $action )
	    {
		die "Malformed return value from $call ".
		  "in $coderef->[$i][1][URISTR]\n".
		    "    ($res, $action)\n";
	    }

	    $result_type ||= $action;
	    if( $action and $result_type != $action )
	    {
		die "Mismatch in returned result types";
	    }

	    if( $action == 0 )
	    {
		# Do nothing
	    }
	    elsif( $action == 1 )
	    {
		$result = $res;
	    }
	    elsif( $action == 2 )
	    {
		push @$result, @$res;
	    }
	    elsif( $action == 3)
	    {
		confess "Result undefined for call $call " unless defined $res;
		$success += $res;
	    }
	    else
	    {
		confess "Action ($action) not implemented";
	    }
	    debug_end( $call, $i, $self );
	}

	# Falling back one step  (not one LEVEL)
	pop @{$self->[HISTORY]};


	if( $result_type == 0 )
	{
	    return 0;
	}
	elsif( $result_type == 1 )
	{
	    return $result;
	}
	elsif( $result_type == 2 )
	{
	    return $result;
	}
	elsif( $result_type == 3 )
	{
	    return 1 if $success;
	    return 0;
	}
	else
	{
	    die "Oh nooo!!!!\n";
	}
    }


    my $types_str = $self->types_as_string;
    $node->[JTK] ||= "--no JTK--";
    die("\nNo function named '$call' defined for $node->[URISTR] ".
	  "($node->[JTK])\n$types_str\n");
}

sub create_jumptable
{
    my( $self, $key ) = @_;

    my $node = $self->[NODE];
    my $funcentry = {};
    my $propentry = {};

    # TODO: Make filters part of signature.  Especially model and
    # language filters.

    # Remember if the codref already has been added for the function
    my %func_count;
    my %prop_count;

    debug_start( "create_jumptable", ' ', $self );

    if( $DEBUG )
    {
	unless( $node->[IDS] )
	{
	    die "No IDS found for $node->[URISTR]\n";
	}
    }

    # Iterate through every interface and type.
    foreach my $interface ( @{interfaces( $node->[IDS] )} )
    {
	debug "..I ".$interface->[URISTR]."\n", 5;
	foreach my $domain ( sort {length($b) <=> length($a)}
			     keys %{$interface->[MODULE_REG]} )
	{
	    debug "    (Checking for $domain in $node->[URISTR])\n", 6;
	    next if $node->[URISTR] !~ /^\Q$domain/;

	    debug "....D $domain\n", 5;

	    my $domain_reg = $interface->[MODULE_REG]{$domain};

	    my $funcs = $domain_reg->{'methods'};
	    my $props = $domain_reg->{'preds'};
	    foreach my $type ( @{$self->type_orderd_list} )
	    {
		if( defined( my $jt = $funcs->{ $type->[NODE][URISTR]} ))
		{
		    debug ".....MT $type->[NODE][URISTR]\n", 5;
		    foreach my $func ( keys %$jt )
		    {
			debug "........F $func()\n", 5;
			# Add The coderefs for this type
			foreach my $coderef ( @{$jt->{$func}} )
			{
			    next if defined $func_count{$func}{$coderef}{$interface};
			    push @{$funcentry->{$func}}, [$coderef,$interface];
			    $func_count{$func}{$coderef}{$interface}++;

			    # TEST
			    if(
				  $func_count{$func}{$coderef}{$interface}
				    > 1 )
			    {
				die "Too many refs!\n";
			    }
			}
		    }
		}

		# DYNTABLE part
		# TODO: use node ID instead of URISTR
		if( defined( my $jt = $props->{ $type->[NODE][URISTR]} ))
		{
		    debug ".....PT $type->[NODE][URISTR]\n", 5;
		    foreach my $func ( keys %$jt )
		    {
			debug "........F $func()\n", 5;
			# Add The coderefs for this type
			foreach my $coderef ( @{$jt->{$func}} )
			{
			    next if defined $prop_count{$func}{$coderef}{$interface};
			    push @{$propentry->{$func}}, [$coderef,$interface];
			    $prop_count{$func}{$coderef}{$interface}++;
			}
		    }
		}
	    }
	}
    }


    debug_end( "create_jumptable", ' ', $self );

    # Insert the jumptable in shared memory
    $JumpJumpTable{$key}=$funcentry;
    $JumpPropTable{$key}=$propentry;
}


sub select_jumptable
{
    my( $self ) = @_;

    debug_start( "select_jumptable", ' ', $self );


    my $node = $self->[NODE];
    my $uri = $node->[URISTR];

    if( $node->[TYPE_ALL] == 2 )
    {
	# Defines the TYPES list
	#
	my $prefix_key = $node->[IDS].'/'.$node->find_prefix_id;
	debug "  ( prefix_key $prefix_key )\n", 2;
	my $key = $prefix_key.'/'.join('-', map $_->[NODE][ID],
				       @{$self->type_orderd_list});
	debug "Jumptable for $uri is defined to $key\n", 2;

	# See also previous create_jumptable() call
	if(not defined $JumpJumpTable{$key})
	{
	    &create_jumptable($self, $key);
	}

	debug "DYNTABLE asigned for $node->[URISTR]\n", 2;
	$node->[JUMPTABLE] = $JumpJumpTable{$key};
	$node->[DYNTABLE] = $JumpPropTable{$key};
	$node->[JTK] = $key;
    }
    else
    {
	$self->init_types;
    }

    if( $DEBUG > 1 )
    {
	debug "D Types for $uri:\n";
	# This lists all types not thinking about what their
	# models are
	foreach my $type_id ( keys %{$node->[TYPE]} )
	{
	    my $type = $self->get_context_by_id( $type_id );
	    # TODO: Check that at least one node declared this
	    # type
	    debug "..$type->[NODE][ID] : $type->[NODE][URISTR]\n";
	}
	debug "\n";
    }

    debug_end("select_jumptable", ' ', $self);
}


1;

