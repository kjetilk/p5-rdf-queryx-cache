#!/usr/bin/perl

use RDF::QueryX::Cache::Manager;
use Redis::Fast;
use CHI;
use LWP::UserAgent::CHICaching;

my $redis = Redis::Fast->new;
my $ua = LWP::UserAgent::CHICaching->(cache => CHI->new( driver => 'Memory', global => 1 ));

$redis->subscribe('prefetch.queries', &execute);

$redis->wait_for_messages(2) while 1;

# This will cache the query response, with the URL in the message as the key
sub execute {
	my ($message) = shift;
	return $ua->get($message)->is_success;
}
