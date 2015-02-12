package RDF::QueryX::Cache::QueryProcessor;

use strict;
use warnings;

use Moo;

with 'RDF::QueryX::Cache::Role::Predicter::Naive';
with 'RDF::QueryX::Cache::Role::Rewriter::Naive';

1;

__END__


=pod

=encoding utf-8

=head1 NAME

RDF::QueryX::Cache::QueryProcessor - Class to process SPARQL queries

=head1 DESCRIPTION

For now, just a class composing L<RDF::QueryX::Cache::Role::Predicter::Naive>
L<RDF::QueryX::Cache::Role::Rewriter::Naive>.



=head1 AUTHOR

Kjetil Kjernsmo E<lt>kjetilk@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2015 by Kjetil Kjernsmo.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
