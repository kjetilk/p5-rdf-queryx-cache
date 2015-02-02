=pod

=encoding utf-8

=head1 PURPOSE

Test the naive predicter.

=head1 AUTHOR

Kjetil Kjernsmo E<lt>kjetilk@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2015 by Kjetil Kjernsmo.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.


=cut

use strict;
use warnings;
use Test::More;
use Test::Moose;
use Moo::Role;
use Redis::Fast;
use CHI;
use Test::RedisServer;
use RDF::Query;

my $redis_server;
eval {
	$redis_server = Test::RedisServer->new;
} or plan skip_all => 'redis-server is required to this test';

my $redis1 = Redis::Fast->new( $redis_server->connect_info );
my $redis2 = Redis::Fast->new( $redis_server->connect_info );

is $redis1->ping, 'PONG', 'Redis Pubsub ping pong ok';
is $redis2->ping, 'PONG', 'Redis store ping pong ok';

{
	package Tmp::Test;
	use Moo;
	with 'RDF::QueryX::Cache::Role::Predicter::Naive';
}

my $basequery =<<'EOQ';
PREFIX dbo: <http://dbpedia.org/ontology/> 

CONSTRUCT {
  ?place a dbo:PopulatedPlace .
  ?place dbo:populationTotal ?pop .
} WHERE {
  ?place a dbo:PopulatedPlace .
  ?place dbo:populationTotal ?pop .
  FILTER (?place < 50)
}
EOQ

my %baseconfig = (
						cache => CHI->new( driver => 'Memory', global => 1 ),
						pubsub => $redis1, store => $redis2,
						remoteendpoint => 'http://localhost/'
					  );

$redis1->subscribe('prefetch.queries', sub { note join ("\t", @_); });

{
	note "Setting up and basic tests";
	my $naive = Tmp::Test->new(query => RDF::Query->new($basequery), %baseconfig);

	does_ok($naive, 'RDF::QueryX::Cache::Role::Predicter');
	does_ok($naive, 'RDF::QueryX::Cache::Role::Predicter::Naive');
	has_attribute_ok($naive, 'query');
	has_attribute_ok($naive, 'threshold');
	can_ok('RDF::QueryX::Cache::Role::Predicter::Naive', 'digest');
	can_ok('RDF::QueryX::Cache::Role::Predicter::Naive', 'analyze');

	note "Testing analyzer";
	is($naive->analyze, 0, 'No triples in the cache yet');
	is($redis1->wait_for_messages(1), 0, 'Not reached threshold yet');
	is($redis2->get('http://dbpedia.org/ontology/populationTotal'), 1, "We counted one pop");
	is($redis2->get('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'), 1, "We counted one rdf:type");
}

$basequery =~ s/< 50/> 5000000/;

{
	note "Testing analyzer with query 2";
	my $naive = Tmp::Test->new(query => RDF::Query->new($basequery), %baseconfig);

	does_ok($naive, 'RDF::QueryX::Cache::Role::Predicter::Naive');

	is($naive->analyze, 0, 'No triples in the cache yet');
	is($redis1->wait_for_messages(1), 0, 'Not reached threshold yet');
	is($redis2->get('http://dbpedia.org/ontology/populationTotal'), 2, "We counted two pops");
	is($redis2->get('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'), 2, "We counted two rdf:types");
}

$basequery =~ s/a dbo:PopulatedPlace/dbo:abstract ?abs/g;

{
	note "Testing analyzer with query 2";
	my $naive = Tmp::Test->new(query => RDF::Query->new($basequery), %baseconfig);

	does_ok($naive, 'RDF::QueryX::Cache::Role::Predicter::Naive');

	is($naive->analyze, 0, 'No triples in the cache yet');
	is($redis1->wait_for_messages(1), 1, 'Reached threshold for pops');
	is($redis2->get('http://dbpedia.org/ontology/abstract'), 1, "We counted one abstract");
	is($redis2->get('http://dbpedia.org/ontology/populationTotal'), 3, "We counted three pops");
	is($redis2->get('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'), 2, "We counted two rdf:types");
}

done_testing;

