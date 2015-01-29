package RDF::QueryX::Cache::Role::Predicter::Naive;

use strict;
use warnings;

use Moo::Role;

with 'RDF::QueryX::Cache::Role::Predicter';

sub digest {
	return "foo";
}


1;
