package RDF::QueryX::Cache::Role::Predicter::Naive;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(Int);

use RDF::Query;

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

		# Then, update the storage so that the cache manager can deal with prefetches
		my $data = $self->store->get($key);
		$data->{score}++;
		$data->{threshold} = $self->threshold;
		$data->{myquery} = 'CONSTRUCT WHERE { ' . $quad->as_sparql . ' }';
		$self->store->set($key, $data, 'never');
	}

#	die Data::Dumper::Dumper($qo->parsed);
}

has threshold ( is => 'rw', isa => Int, default => sub { 3 });
#has myquery ( is => 'rw', isa => Str, default => sub { 3 });


sub digest {
	my ($self, $quad) = @_;
	if ($quad->predicate->is_resource) {
		return $quad->predicate->uri_value;
	} else {
		return undef;
	}
}


1;
