package RDF::QueryX::Cache::Role::Predicter::Naive;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(Int HashRef);

use RDF::Query;
use RDF::Query::Algebra qw(bgp triple);
use RDF::Trine qw(variable);
use URI::Escape::XS qw/uri_escape/;
use Scalar::Util qw(refaddr);
use Carp;

with 'RDF::QueryX::Cache::Role::Predicter';


=pod

=encoding utf-8

=head1 NAME

RDF::QueryX::Cache::Role::Predicter::Naive - A plugin for a naive predicter for SPARQL prefetching

=head1 SYNOPSIS

To compose this to a class, do e.g.:

  package MyPredicter;
  use Moo;
  with 'RDF::QueryX::Cache::Role::Predicter::Naive';

and then you can do for example:

   use Redis::Fast;
   my $redis = Redis::Fast->new;
  	my $naive = MyPredicter->new(query => RDF::Query->new('CONSTRUCT WHERE { ?foo a :Bar . }'),
						              cache => CHI->new( driver => 'Memory', global => 1 ),
					                 store => $redis,
						              remoteendpoint => 'http://localhost/');
   $naive->analyze;

Then, you can wait for queries to prefetch.

   use LWP::Simple;
   use Redis::Fast;
   my $subscribe = Redis::Fast->new;
   $subscribe->subscribe('prefetch.queries', &get);
   $subscribe->wait_for_messages(1) while 1;

TODO: The final block here has not been tested.


=head1 DESCRIPTION

This is a L<Moo::Role> that needs to be composed into a class to do
any real work. It implements the API found in
L<RDF::QueryX::Cache::Role::Predicter>. It is planned that the actual
classes that uses these roles are to have a plugin architecture, to
make it easy to write other predicter plugins.

This plugin simply looks for predicates that occur more than a certain
number of times.

=head2 Constructor

=over

=item C<< new(%attributes) >>

Moose-style constructor function.

=back

=head2 Attributes and methods

These attributes may be passed to the constructor to set them, or
called like methods to get them, see
L<RDF::QueryX::Cache::Role::Predicter> for other attributes.

=over

=item C<< digest >>

Will return the URI value of the predicate if present, or C<undef> if not.

=item C<< threshold >>

The number of times a predicate must occur to be legible for prefetching.

=item C<< analyze >>

Loops the triple patterns, checks if any of them have a cached result
(TODO) and increments the number of times a certain predicate has been
seen in the store. When that number exceeds the C<threshold>, a single
triple pattern query with that predicate is published to the Redis
store with topic C<prefetch.queries>.

=back

=cut

sub analyze {
	my $self = shift;
	my $qo = $self->query;
	my $count = 0;
	# TODO: Return undef if we can't process the query
	foreach my $quad ($qo->pattern->subpatterns_of_type('RDF::Trine::Statement')) {
		my $key = $self->digest($quad);
		next unless ($key);

		# Update the storage and push an event so that the cache manager can deal with prefetches
		$self->store->incr($key);
		my $count = $self->store->get($key);
		if ($count == $self->threshold) { # Fails if two clients are updating at the same time
			$self->store->publish('prefetch.queries', $key);
		}

		# Save the keys of valid cache entries
		if ($key && ($self->cache->is_valid($key))) {
			$self->add_local_keys($key);
			$count++;
		}
	}
	return $count;
}

has threshold => ( is => 'rw', isa => Int, default => sub { 3 });


sub digest {
	my ($self, $quad) = @_;
	if ($quad->predicate->is_resource) {
		my $triple = RDF::Query::Algebra::Triple->new(variable('s'), $quad->predicate, variable('o'));
		my $uri = URI->new($self->remoteendpoint . '?query=' . uri_escape('CONSTRUCT WHERE { ' . $triple->as_sparql . ' }'));
		return $uri->canonical->uri_value;
	} else {
		return undef;
	}
}

1;


=head1 AUTHOR

Kjetil Kjernsmo E<lt>kjetilk@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2015 by Kjetil Kjernsmo.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
