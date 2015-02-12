package RDF::QueryX::Cache::Role::Predicter;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(InstanceOf Str Int ArrayRef);
use MooX::HandlesVia;
use Scalar::Util qw(blessed);
use Data::Dumper;

use RDF::Query;

=pod

=encoding utf-8

=head1 NAME

RDF::QueryX::Cache::Role::Predicter - API and partial implementation of plugins to decide queries to prefetch

=head1 SYNOPSIS

See e.g. L<RDF::QueryX::Cache::Role::Predicter::Naive> for
documentation on how to compose a class in practice.

=head1 DESCRIPTION

This is a L<Moo::Role> that needs to be composed into a class to do
any real work. It contains implementations of core functionality as
well as requirements for the composed class. As such, it is both an
implementation and API documentation. In the future, the present
architecture should be trivially extensible to a plugin architecture
where the predicters are plugins, so that there are many different
ways to implement them. Obviously, using existing techniques to query
similarity is a prime example of such plugins.

=head2 Constructor

=over

=item C<< new(%attributes) >>

Moose-style constructor function.

=back

=head2 Attributes

These attributes may be passed to the constructor to set them, or
called like methods to get them.

=over

=item C<< query >>

A L<RDF::Query> object containing the SPARQL query to analyze.

=cut


has query => (is => 'ro', 
				  isa => InstanceOf['RDF::Query'],
				  required => 1
				 );

=item C<< remoteendpoint >>

The URL of the remote endpoint that the query is directed towards, as a string.

=cut

has remoteendpoint => (is => 'ro', isa => Str, required => 1);

=item C<< store >>

A L<Redis::Fast> object. This has two purposes: First, to store any
data the analyzer needs to persist to decide when to prefetch. Second,
it uses Redis' publish-subscribe system to publish the URLs containing
queries that the prefetcher should fetch.

=cut

has store => (is => 'ro',
				  isa => InstanceOf['Redis::Fast'],
				  required => 1
				 );

=item C<< cache >>

A L<CHI> driver to actually cache the query results.

=cut


has cache => (is => 'ro',
				  isa => InstanceOf['CHI::Driver'],
				 );


=item C<< localtriples >>, C<< add_localtriples >>

An arrayref of triple patterns that have fresh results the local
cache.

=cut

has localtriples => (is => 'rw',
							isa => ArrayRef,
							handles_via => 'Array',
							handles => {
											add_localtriples => 'push' 
										  },
							default => sub {[]});



=item C<< remotetriples >>, C<< add_remotetriples >>

An arrayref of triple patterns that doesn't have fresh results the
local cache.

=back

=cut

has remotetriples => (is => 'rw',
							 isa => ArrayRef,
							 handles_via => 'Array',
							 handles => {
											 add_remotetriples => 'push' 
											},
							 default => sub {[]});


=item C<< local_keys >>, C<< add_local_keys >>

An arrayref of keys in use for the local cache.

=back

=cut

has local_keys => (is => 'rw',
				 isa => ArrayRef,
				 handles_via => 'Array',
				 handles => {
								 add_local_keys => 'push' 
								},
				 default => sub {[]});



=head2 Required methods or attributes

The following must be implemented by a consuming class (or a role it
also consumes):

=over

=item C<< digest >>

A method that creates a unique digest suitable as a cache identifier
for the result of a part of a query. If the class cannot cache the
given part, it must return C<undef>.

=item C<< threshold >>

An attribute setting a threshold for when a query part is prevalent
enough to be prefetched.

=item C<< analyze >>

This method should analyze the query to see if parts of it should be
prefetched. It must do two things: 1) It must identify the quad
patterns that can be evaluated locally since they are in the local
cache, by updating C<localtriples>. 2) It must publish queries to the
C<store>, by creating a SPARQL CONSTRUCT query, URL-encode it to the
endpoint URL according to the SPARQL protocol, and publish it to a
topic named C<prefetch.queries>.

If it found any query parts that are cached locally, it must return a
true value. To actively decline to process a certain query, return
C<undef>.

=back

=cut

requires 'digest';
requires 'threshold';
requires 'analyze';

1;

__END__

=head1 TODO

This is so early, it is still a braindump. First of all, I'm not sure
C<remotetriples> has any role to play, and C<threshold> may better be
a private constant. We'll see.

=head1 AUTHOR

Kjetil Kjernsmo E<lt>kjetilk@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2015 by Kjetil Kjernsmo.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
