#!/usr/bin/perl

use Redis::Fast;
use CHI;
use LWP::UserAgent::CHICaching;

my $redis = Redis::Fast->new;
my $ua = LWP::UserAgent::CHICaching->new(cache => CHI->new( driver => 'Redis', namespace =>'cache' ));

$redis->subscribe('prefetch.queries', 
						# This will cache the query response, with the URL in the message as the key
						sub {
							my ($message) = shift;
							warn $message;
							my $res = $ua->get($message);
							warn "RES: " . $res->content;
							return $res->is_success;
						}
					  );

$redis->wait_for_messages(2) while 1;
