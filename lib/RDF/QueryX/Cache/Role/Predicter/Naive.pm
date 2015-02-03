package RDF::QueryX::Cache::Role::Predicter::Naive;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(Int);

use RDF::Query;
use RDF::Trine qw(variable);
use URI::Escape::XS qw/uri_escape/;

with 'RDF::QueryX::Cache::Role::Predicter';

sub analyze {
	my $self = shift;
	my $qo = $self->query;
	my $count = 0;
	# TODO: Return undef if we can't process the query
	foreach my $quad ($qo->pattern->subpatterns_of_type('RDF::Trine::Statement')) {
		my $key = $self->digest($quad);

		# First, create the patterns used to evaluate the query
		if ($key && ($self->cache->is_valid($key))) {
			$self->add_localtriples($quad);
			$count++;
		} else {
			$self->add_remotetriples($quad);
		}

		next unless ($key);

		# Then, update the storage and push an event so that the cache manager can deal with prefetches
		$self->store->incr($key);
		my $count = $self->store->get($key);
		if ($count == $self->threshold) { # Fails if two clients are updating at the same time
			my $triple = RDF::Query::Algebra::Triple->new(variable('s'), $quad->predicate, variable('o'));
			$self->store->publish('prefetch.queries', $self->remoteendpoint . '?query=' . uri_escape('CONSTRUCT WHERE { ' . $triple->as_sparql . ' }'));
		}

	}
	return $count;
}

has threshold => ( is => 'rw', isa => Int, default => sub { 3 });


sub digest {
	my ($self, $quad) = @_;
	if ($quad->predicate->is_resource) {
		return $quad->predicate->uri_value;
	} else {
		return undef;
	}
}


1;
