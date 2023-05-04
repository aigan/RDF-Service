#  $Id: Constants.pm,v 1.28 2001/04/10 13:05:24 aigan Exp $  -*-perl-*-

package RDF::Service::Constants;

#=====================================================================
#
# DESCRIPTION
#   Export the constants used in Resource objects
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
use vars qw( @EXPORT_OK %EXPORT_TAGS );


# The constant list should be orderd by frequency, in order to shorten
# the average array lenght.

# Resouce
use constant IDS             =>  1; #Interface Domain Signature
use constant URISTR          =>  2;
use constant ID              =>  3;
use constant TYPE            =>  4; #hash of type_id => { model_id => 1 }
use constant TYPE_ALL        =>  5; #1 = static, 2=dynamic
use constant TYPE_SOLID      =>  6; #1 = solid
use constant REV_TYPE        =>  7; #hash of res_id => { model_id => 1 }
use constant REV_TYPE_ALL    =>  8; #1 = static, 2=dynamic
use constant REV_TYPE_SOLID  =>  9; #1 = solid
use constant JUMPTABLE       => 10; #{function=>[[coderef,interface]]}
use constant DYNTABLE        => 11; #{function=>[[coderef,interface]]}
use constant PRIVATE         => 13; #hash of interface_id => {%data}
use constant MODEL           => 14; #$model_node
use constant ALIASFOR        => 15; #node
use constant REV_PRED        => 16; #array of $arc_node
use constant REV_PRED_ALL    => 17; #
use constant REV_PRED_SOLID  => 18;
use constant REV_SUBJ        => 19; #(props) hash of pred_id=>[$arc_node]
use constant REV_SUBJ_ALL    => 20; #rev subj
use constant REV_SUBJ_PREDS  => 21; #hash of pred_id=>1, means all preds
use constant REV_SUBJ_I      => 22;
use constant REV_SUBJ_SOLID  => 23;
use constant REV_OBJ         => 24; #(rev_props)
use constant REV_OBJ_ALL     => 25; # rev obj
use constant REV_OBJ_PREDS   => 26;
use constant REV_OBJ_I       => 27;
use constant REV_OBJ_SOLID   => 28;
use constant JTK             => 29; #Jumptable key  (just for debugging)
use constant MULTI           => 30; # Multipple models for the implicit arcs
use constant SOLID           => 31; # Is it retrievable from a interface?
use constant LOCAL           => 32; # 1 = does not exist in interfaces
use constant RUNLEVEL        => 33; # 0 = startup
use constant DECIDES         => 34; #hash of source => [dest]

# Resource li
use constant MEMBER          => 35;

# Resource Statement
use constant PRED            => 36; #node
use constant SUBJ            => 37; #node
use constant OBJ             => 38; #node

# Resource Literal
use constant VALUE           => 41; #ref to string
use constant LANG            => 42; #node

# Resource Model / container
## REV_MODEL implicit arc belongs to base_model
use constant REV_MODEL       => 44;  # hash of res_id => node
use constant REV_MODEL_ALL   => 45;
use constant REV_MODEL_SOLID => 46;
use constant SELECTION       => 47;  # Digest content
use constant CONTENT         => 48;  # Expanded content
use constant CONTENT_ALL     => 49;  # content solid
use constant READONLY        => 50;  # TODO: To be used?

# Resource Interface
use constant PREFIX          => 51;
use constant MODULE_NAME     => 52;
use constant MODULE_REG      => 53; #hash of prefix => {typeURI => JUMPTABLE}

# Resource Service
use constant INTERFACES      => 56;  # node
use constant ABBREV          => 57;  # abbrevations for predicates

# Namespaces
use constant NS_RDF          => "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
use constant NS_RDFS         => "http://www.w3.org/2000/01/rdf-schema#";
use constant NS_LS           => "http://uxn.nu/rdf/2000/09/19/local-schema/";
use constant NS_LD           => "http://uxn.nu/rdf/2000/09/19/local-data/";
use constant NS_DAML         => "http://www.daml.org/2000/12/daml+oil#";
use constant NS_XML          => "xml:"; # TODO: Fix me!


# Context
use constant CONTEXT         => 1;
use constant NODE            => 2;
use constant WMODEL          => 3; # The working model (Context)
use constant MEMORY          => 4; # Same as PRIVATE
use constant HISTORY         => 5; # call history. Hash of "@_"=>1
use constant SESSION         => 6; # Ref to service node

# Trimming
#use constant NO_TRIM         => 0;
#use constant TRIM_PRED       => 1;
#use constant TRIM            => 2;



my @RESOURCE = qw( IDS URISTR ID TYPE TYPE_ALL TYPE_SOLID REV_TYPE
		   REV_TYPE_ALL REV_TYPE_SOLID JUMPTABLE DYNTABLE NS
		   NAME PRIVATE ALIASFOR MODEL REV_SUBJ REV_SUBJ_ALL
		   REV_SUBJ_PREDS REV_SUBJ_I REV_SUBJ_SOLID REV_PRED
		   REV_PRED_ALL REV_PRED_SOLID REV_OBJ REV_OBJ_ALL
		   REV_OBJ_PREDS REV_OBJ_I REV_OBJ_SOLID JTK MULTI
		   SOLID LOCAL RUNLEVEL DECIDES );

my @INTERFACE = qw( PREFIX MODULE_NAME MODULE_REG );
my @LITERAL   = qw( VALUE LANG );
my @CONTAINER = qw( REV_MODEL REV_MODEL_ALL REV_MODEL_SOLID SELECTION
		    CONTENT CONTENT_ALL READONLY );
my @STATEMENT = qw( SUBJ PRED OBJ );
my @LI        = qw( MEMBER );
my @RDF       = qw( INTERFACES ABBREV );
my @NAMESPACE = qw( NS_RDF NS_RDFS NS_LS NS_LD NS_DAML );
my @CONTEXT   = qw( CONTEXT NODE WMODEL MEMORY HISTORY SESSION );
my @DEPENDS   = qw( DPROPS DREVPROPS );

my @ALL = (@INTERFACE, @RESOURCE, @LITERAL, @CONTAINER, @STATEMENT, @LI,
	   @RDF, @NAMESPACE, @CONTEXT, '$Schema' );

@EXPORT_OK = ( @ALL );
%EXPORT_TAGS = (
    'all'        => [@ALL],
    'resource'   => [@RESOURCE],
    'interface'  => [@RESOURCE,@INTERFACE],
    'literal'    => [@RESOURCE,@LITERAL],
    'container'  => [@RESOURCE,@CONTAINER],
    'statement'  => [@RESOURCE,@STATEMENT],
    'li'         => [@RESOURCE,@LI],
    'rdf'        => [@RESOURCE, @RDF, @CONTAINER],
    'namespace'  => [@NAMESPACE],
    'context'    => [@CONTEXT],
    );





##### DATA

# Type ref is used by type_orderd_list() in Context.
#
# NS_RDF.'type' => \(NS_RDFS.'Class'),

our $Schema =
{
    NS_LS.'level' =>
    {
        NS_RDFS.'label' => 'level',
	NS_RDF.'type' =>  \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDFS.'Class'),
	NS_RDFS.'range' => \ (NS_RDFS.'Literal'),
    },
    NS_LS.'size' =>
    {
        NS_RDFS.'label' => 'size',
	NS_RDF.'type' =>  \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDFS.'Container'),
	NS_RDFS.'range' => \ (NS_RDFS.'Literal'),
    },
    NS_LS.'updated' =>
    {
        NS_RDFS.'label' => 'updated',
	NS_RDF.'type' =>  \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_LS.'Model'),
	NS_RDFS.'range' => \ (NS_RDFS.'Literal'),
    },
    NS_LS.'agent' =>
    {
        NS_RDFS.'label' => 'agent',
	NS_RDF.'type' =>  \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_LS.'Model'),
	NS_RDFS.'range' => \ (NS_RDFS.'Literal'),
    },
    NS_LS.'Interface' =>
    {
	NS_LS.'ns' => \ (NS_LS),
	NS_RDFS.'label' => 'Interface',
        NS_LS.'level' => '1',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
    },
    NS_LS.'interface' =>
    {
	NS_RDFS.'label' => 'interface',
	NS_RDF.'type' =>  \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDFS.'Resource'),
	NS_RDFS.'range' => \ (NS_LS.'Interface'),
    },
    NS_LS.'Selection' =>
    {
	NS_RDFS.'label' => 'Selection',
        NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_RDFS.'Container'),
    },
    NS_LS.'Model' =>
    {
	NS_RDFS.'label' => 'Model',
        NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_RDFS.'Container'),
    },
    NS_LS.'model' =>
    {
	NS_RDFS.'label' => 'model',
	NS_RDF.'type' =>  \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDFS.'Resource'),
	NS_RDFS.'range' => \ (NS_LS.'Model'),
    },
    NS_LS.'Service' =>
    {
	NS_RDFS.'label' => 'Service',
        NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_LS.'Model'),
    },
    NS_LS.'True' => # No property if false
    {
	NS_RDFS.'label' => 'True',
        NS_LS.'level' => '1',
    },

########################

    NS_LS.'Query' =>
    {
	NS_RDFS.'label' => 'Query',
	NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_RDFS.'Class'),
    },
    NS_LS.'Form/Widget' =>
    {
	NS_RDFS.'label' => 'Form Widget',
	NS_LS.'level' => '1',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
    },
    NS_LS.'Form/Widget/SubContainer' =>
    {
	NS_RDFS.'label' => 'Form Widget: Sub Container',
	NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_LS.'Form/Widget'),
    },

########################

    NS_DAML.'unionOf' =>
    {
	NS_RDFS.'label' => 'unionOf',
	NS_RDFS.'domain' => \ (NS_RDFS.'Class'),
	NS_RDFS.'range' => \ (NS_RDFS.'Container'),
    },

#########################

    NS_RDFS.'Resource' =>
    {
	NS_RDFS.'label' => 'Resource',
        NS_LS.'level' => '0',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'label' => 'Resource',
	NS_RDFS.'comment' => 'The most general class',
    },

    NS_RDF.'type' =>
    {
	NS_RDFS.'label' => 'type',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'range' => \ (NS_RDFS.'Class'),
    },
    NS_RDFS.'comment' =>
    {
	NS_RDFS.'label' => 'comment',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDFS.'Resource'),
	NS_RDFS.'range' => \ (NS_RDFS.'Literal'),
    },
    NS_RDFS.'label' =>
    {
	NS_RDFS.'label' => 'label',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDFS.'Resource'),
	NS_RDFS.'range' => \ (NS_RDFS.'Literal'),
    },
    NS_RDFS.'Class' =>
    {
	NS_RDFS.'label' => 'Class',
        NS_LS.'level' => '1',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_RDFS.'Resource'),
    },
    NS_RDFS.'subClassOf' =>
    {
	NS_RDFS.'label' => 'subClassOf',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDFS.'Class'),
	NS_RDFS.'range' => \ (NS_RDFS.'Class'),
    },
    NS_RDFS.'subPropertyOf' =>
    {
	NS_RDFS.'label' => 'subPropertyOf',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDF.'Property'),
	NS_RDFS.'range' => \ (NS_RDF.'Property'),
    },
    NS_RDFS.'seeAlso' =>
    {
	NS_RDFS.'label' => 'seeAlso',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDFS.'Resource'),
	NS_RDFS.'range' => \ (NS_RDFS.'Resource'),
    },
    NS_RDFS.'isDefinedBy' =>
    {
	NS_RDFS.'label' => 'isDefinedBy',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDFS.'Resource'),
	NS_RDFS.'range' => \ (NS_RDFS.'Resource'),
    },
    NS_RDFS.'ConstraintResource' =>
    {
	NS_RDFS.'label' => 'ConstraintResource',
        NS_LS.'level' => '1',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
    },
    NS_RDFS.'ConstraintProperty' =>
    {
	NS_RDFS.'label' => 'ConstraintProperty',
        NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => [ \ (NS_RDF.'Property'),
				\ (NS_RDFS.'ConstraintResource'),
				],
    },
    NS_RDFS.'domain' =>
    {
	NS_RDFS.'label' => 'domain',
	NS_RDF.'type' => \ (NS_RDFS.'ConstraintProperty'),
	NS_RDFS.'domain' => \ (NS_RDF.'Property'),
	NS_RDFS.'range' => \ (NS_RDFS.'Class'),
    },
    NS_RDFS.'range' =>
    {
	NS_RDFS.'label' => 'range',
	NS_RDF.'type' => \ (NS_RDFS.'ConstraintProperty'),
	NS_RDFS.'domain' => \ (NS_RDF.'Property'),
	NS_RDFS.'range' => \ (NS_RDFS.'Class'),
    },
    NS_RDF.'Property' =>
    {
	NS_RDFS.'label' => 'Property',
        NS_LS.'level' => '1',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
    },
    NS_RDFS.'Literal' =>
    {
	NS_RDFS.'label' => 'Literal',
        NS_LS.'level' => '1',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
    },
    NS_RDF.'Statement' =>
    {
	NS_RDFS.'label' => 'Statement',
        NS_LS.'level' => '1',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
    },
    NS_RDF.'subject' =>
    {
	NS_RDFS.'label' => 'subject',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDF.'Statement'),
	NS_RDFS.'range' => \ (NS_RDFS.'Resource'),
    },
    NS_RDF.'predicate' =>
    {
	NS_RDFS.'label' => 'predicate',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDF.'Statement'),
	NS_RDFS.'range' => \ (NS_RDF.'Property'),
    },
    NS_RDF.'object' =>
    {
	NS_RDFS.'label' => 'object',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
	NS_RDFS.'domain' => \ (NS_RDF.'Statement'),
    },
    NS_RDFS.'Container' =>
    {
	NS_RDFS.'label' => 'Container',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
        NS_LS.'level' => '1',
    },
    NS_RDF.'Bag' =>
    {
	NS_RDFS.'label' => 'Bag',
        NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_RDFS.'Container'),
    },
    NS_RDF.'Seq' =>
    {
	NS_RDFS.'label' => 'Seq',
        NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_RDFS.'Container'),
    },
    NS_RDF.'Alt' =>
    {
	NS_RDFS.'label' => 'Alt',
        NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_RDFS.'Container'),
    },
    NS_RDFS.'ContainerMembershipProperty' =>
    {
	NS_RDFS.'label' => 'ContainerMembershipProperty',
        NS_LS.'level' => '2',
	NS_RDF.'type' => \ (NS_RDFS.'Class'),
	NS_RDFS.'subClassOf' => \ (NS_RDF.'Property'),
    },
    NS_RDF.'value' =>
    {
	NS_RDFS.'label' => 'value',
	NS_RDF.'type' => \ (NS_RDF.'Property'),
    },
};


1;
