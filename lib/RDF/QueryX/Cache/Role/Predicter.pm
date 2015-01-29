package RDF::QueryX::Cache::Role::Predicter;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(InstanceOf Str Bool Maybe Int HashRef);
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

requires 'digest';
#requires '';

1;
