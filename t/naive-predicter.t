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

my $naive = Tmp::Test->new(query => 'FOO',
									cache => CHI->new( driver => 'Memory', global => 1 ),
									pubsub => $redis1, store => $redis2,
									remoteendpoint => 'http://localhost/');


does_ok($naive, 'RDF::QueryX::Cache::Role::Predicter');
does_ok($naive, 'RDF::QueryX::Cache::Role::Predicter::Naive');
has_attribute_ok($naive, 'query');
has_attribute_ok($naive, 'threshold');
can_ok('RDF::QueryX::Cache::Role::Predicter::Naive', 'digest');
can_ok('RDF::QueryX::Cache::Role::Predicter::Naive', 'analyze');





done_testing;

