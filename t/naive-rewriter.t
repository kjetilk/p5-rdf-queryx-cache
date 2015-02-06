=pod

=encoding utf-8

=head1 PURPOSE

Test the naive query rewriter.

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
use URI;
use URI::Escape::XS qw/uri_unescape/;

my $redis_server;
eval {
	$redis_server = Test::RedisServer->new;
} or plan skip_all => 'redis-server is required to this test';

my $redis = Redis::Fast->new( $redis_server->connect_info );

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
}
WHERE {
        ?place a dbo:PopulatedPlace .
        ?place dbo:populationTotal ?pop .
        FILTER( (?pop < 50) ) .
}
EOQ

my %baseconfig = (
						cache => CHI->new( driver => 'Memory', global => 1 ),
					   store => $redis,
						remoteendpoint => 'http://remote.example.org/sparql'
					  );

{
	note "Setting up and basic tests";
	my $naive = Tmp::Test->new(query => RDF::Query->new($basequery), %baseconfig);

	can_ok('RDF::QueryX::Cache::Role::Predicter::Naive', 'analyze');

	note "Testing query 1";
	$naive->rewrite;
	warn $naive->query->as_sparql;
}

my $nolocal =<<'EOQ';
PREFIX dbo: <http://dbpedia.org/ontology/>
 CONSTRUCT {
        ?place a dbo:PopulatedPlace .
        ?place dbo:populationTotal ?pop .
}
WHERE {
 SERVICE <http://remote.example.org/sparql> {
        ?place a dbo:PopulatedPlace .
        ?place dbo:populationTotal ?pop .
        FILTER( (?pop < 50) ) .
 }
}
EOQ

my $aremote =<<'EOQ';
PREFIX dbo: <http://dbpedia.org/ontology/>
 CONSTRUCT {
        ?place a dbo:PopulatedPlace .
        ?place dbo:populationTotal ?pop .
}
WHERE {
 SERVICE <http://remote.example.org/sparql> {
        ?place a dbo:PopulatedPlace .
 }
        ?place dbo:populationTotal ?pop .
        FILTER( (?pop < 50) ) .

}
EOQ

my $popremote =<<'EOQ';
PREFIX dbo: <http://dbpedia.org/ontology/>
 CONSTRUCT {
        ?place a dbo:PopulatedPlace .
        ?place dbo:populationTotal ?pop .
}
WHERE {
        ?place a dbo:PopulatedPlace .
 SERVICE <http://remote.example.org/sparql> {
        ?place dbo:populationTotal ?pop .
        FILTER( (?pop < 50) ) .
 }
}
EOQ

