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
	sub new { return bless {}, 'Tmp::Test'}; 
}

my $naive = Tmp::Test->new;
"Moo::Role"->apply_roles_to_object($naive, 'RDF::QueryX::Role::Predicter::Naive');

does_ok($naive, 'RDF::QueryX::Role::Predicter');
has_attribute_ok($naive, 'query');
can_ok('RDF::QueryX::Role::Predicter::Naive', 'digest');



done_testing;

