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

{
	package Tmp::Test;
	use Moo;
	with 'RDF::QueryX::Cache::Role::Predicter::Naive';
}

my $naive = Tmp::Test->new(query => 'FOO');


does_ok($naive, 'RDF::QueryX::Cache::Role::Predicter');
does_ok($naive, 'RDF::QueryX::Cache::Role::Predicter::Naive');
has_attribute_ok($naive, 'query');
can_ok('RDF::QueryX::Cache::Role::Predicter::Naive', 'digest');



done_testing;

