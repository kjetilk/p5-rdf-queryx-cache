package RDF::QueryX::Cache::Role::Predicter;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(InstanceOf Str Int ArrayRef);
use MooX::HandlesVia;

use RDF::Query;

has query => (is => 'ro', 
				  isa => Str | InstanceOf['RDF::Query'],
				  builder => '_build_query',
				  required => 1
				 );


sub _build_query {
	my ($self, $query) = @_;
	if ($query->isa('RDF::Query')) {
		return $query;
	} else {
		return RDF::Query->new($query);
	}
}

has remoteendpoint => (is => 'ro', isa => Str, required => 1);


has store => (is => 'ro',
				  isa => InstanceOf['Redis::Fast'],
				  required => 1
				 );

has cache => (is => 'ro',
				  isa => InstanceOf['CHI::Driver'],
				  required => 1
				 );

has localtriples  => (is => 'rw', isa => ArrayRef['RDF::Query::Algebra::Quad'], handles_via => 'Array');
has remotetriples => (is => 'rw', isa => ArrayRef['RDF::Query::Algebra::Quad'], handles_via => 'Array');


requires 'digest';
requires 'threshold';
requires 'analyze';

1;
