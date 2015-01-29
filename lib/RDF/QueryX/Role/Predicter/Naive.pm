package RDF::QueryX::Role::Predicter::Naive;

use strict;
use warnings;

use Moo::Role;

with 'RDF::QueryX::Role::Predicter';

sub digest {
	return "foo";
}


1;
