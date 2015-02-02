package RDF::QueryX::Cache::Role::Predicter::Naive;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(Int);

use RDF::Query;
use URI::Escape::XS qw/uri_escape/;

with 'RDF::QueryX::Cache::Role::Predicter';

sub analyze {
	my $self = shift;
	my $qo = $self->query;
	my $count = 0;
	# TODO: Return undef if we can't process the query
	foreach my $triple (@{$qo->pattern->triples}) {
		my $key = $self->digest($triple);

		# First, create the patterns used to evaluate the query
		if ($key && ($self->cache->is_valid($key))) {
			$self->add_localtriples($triple);
			$count++;
		} else {
			$self->add_remotetriples($triple);
		}

		next unless ($key);

		# Then, update the storage and push an event so that the cache manager can deal with prefetches
		$self->store->incr($key);
		my $count = $self->store->get($key);
		if ($count == $self->threshold) { # Fails if two clients are updating at the same time
			$self->store->publish('prefetch.queries', $self->remoteendpoint . '?query=' . uri_escape('CONSTRUCT WHERE { ' . $triple->as_sparql . ' }'));
		}

	}
	return $count;
}

has threshold => ( is => 'rw', isa => Int, default => sub { 3 });


sub digest {
	my ($self, $triple) = @_;
	if ($triple->predicate->is_resource) {
		return $triple->predicate->uri_value;
	} else {
		return undef;
	}
}


1;
