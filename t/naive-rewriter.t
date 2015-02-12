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
use RDF::Trine qw(statement iri variable);
use URI;
use URI::Escape::XS qw/uri_unescape/;
use Data::Dumper;

use_ok('RDF::QueryX::Cache::QueryProcessor');
my $redis_server;
eval {
	$redis_server = Test::RedisServer->new;
} or plan skip_all => 'redis-server is required to this test';

my $redis = Redis::Fast->new( $redis_server->connect_info );

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

note "Setting up and basic tests";

my $q = RDF::Query->new($basequery, lang=>'sparql11');
warn Dumper($q->pattern);
my $naive = RDF::QueryX::Cache::QueryProcessor->new(query => $q, %baseconfig);

can_ok('RDF::QueryX::Cache::Role::Predicter::Naive', 'analyze');
can_ok('RDF::QueryX::Cache::Role::Rewriter::Naive', 'rewrite');

note "Testing query 1";

my $nolocalrw = $naive->rewrite;
isa_ok($nolocalrw, 'RDF::Query');

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

$nolocal = RDF::Query->new($nolocal)->pattern->as_sparql;
warn "No local Have\n" . $nolocal;
warn "No local Got\n" . $nolocalrw->as_sparql;

TODO: {
	local $TODO = "Must fix FILTER";
is($nolocalrw->as_sparql, $nolocal, "Query with no locals ok");
}

my $aremotekey = $naive->digest(statement(variable('place'), 
														iri('http://dbpedia.org/ontology/populationTotal'),
														variable('pop')));


$naive->cache->set($aremotekey, '1');


my $aremoterw = $naive->rewrite;
isa_ok($aremoterw, 'RDF::Query');


my $aremote =<<'EOQ';
PREFIX dbo: <http://dbpedia.org/ontology/>
 CONSTRUCT {
        ?place a dbo:PopulatedPlace .
        ?place dbo:populationTotal ?pop .
}
WHERE {
        ?place dbo:populationTotal ?pop .
 SERVICE <http://remote.example.org/sparql> {
        ?place a dbo:PopulatedPlace .
 }
        FILTER( (?pop < 50) ) .

}
EOQ

$aremote = RDF::Query->new($aremote)->pattern->as_sparql;
warn "One remote Have\n" . $aremote;
warn "One remote Got\n" . $aremoterw->as_sparql;

is($aremoterw->as_sparql, $aremote, "Query with one remote ok");


my $popremotekey = $naive->digest(statement(variable('place'), 
													  iri('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'), 
													  iri('http://dbpedia.org/ontology/PopulatedPlace')));

$naive->cache->remove($aremotekey);
$naive->cache->set($popremotekey, '1');

my $popremoterw = $naive->rewrite;
isa_ok($popremoterw, 'RDF::Query');

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

warn Dumper(RDF::Query->new($popremote));
warn Dumper($popremoterw);
$popremote = RDF::Query->new($popremote)->pattern->as_sparql;
warn "One remote Have\n" . $popremote;
warn "One remote Got\n" . $popremoterw->as_sparql;

TODO: {
	local $TODO = "Must fix FILTER";
is($popremoterw->as_sparql, $popremote, "Query with population as remote ok");
}

done_testing;
