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
	foreach my $quad ($qo->pattern->quads) {
		my $key = $self->digest($quad);

		# First, create the patterns used to evaluate the query
		if ($key && ($self->cache->is_valid($key))) {
			$self->localtriples->push($quad);
		} else {
			$self->remotetriples->push($quad);
		}

		next unless ($key);

		# Then, update the storage and push an event so that the cache manager can deal with prefetches
		$self->store->incr($key);
		my $count = $self->store->get($key);
		if ($count == $self->threshold) { # Fails if two clients are updating at the same time
			$self->pubsub->publish('prefetch.queries', $self->remoteendpoint . '?query=' . uri_escape('CONSTRUCT WHERE { ' . $quad->as_sparql . ' }'));
		}

	}
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
