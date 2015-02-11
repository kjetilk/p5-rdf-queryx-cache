package RDF::QueryX::Cache::Role::Rewriter::Naive;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(Int HashRef);

use RDF::Query;
use RDF::Query::Algebra qw(bgp triple);
use RDF::Trine qw(variable);
use URI::Escape::XS qw/uri_escape/;
use Scalar::Util qw(refaddr);
use Carp;

with 'RDF::QueryX::Cache::Role::Rewriter';
with 'RDF::QueryX::Cache::Role::Predicter';


=pod

=encoding utf-8

=head1 NAME

RDF::QueryX::Cache::Role::Rewriter::Naive - A plugin for a naive predicter for SPARQL prefetching

=head1 SYNOPSIS

To compose this to a class, do e.g.:

  package MyRewriter;
  use Moo;
  with 'RDF::QueryX::Cache::Role::Predicter::Naive';
  with 'RDF::QueryX::Cache::Role::Rewriter::Naive';

and then you can do for example:

   use Redis::Fast;
   my $redis = Redis::Fast->new;
  	my $naive = MyRewriter->new(query => RDF::Query->new('CONSTRUCT WHERE { ?foo a :Bar . }'),
						              cache => CHI->new( driver => 'Memory', global => 1 ),
					                 store => $redis,
						              remoteendpoint => 'http://localhost/');
   $naive->analyze;
   my $newquery = $naive->rewrite;

Then, you can wait for queries to prefetch.

   use LWP::Simple;
   use Redis::Fast;
   my $subscribe = Redis::Fast->new;
   $subscribe->subscribe('prefetch.queries', &get);
   $subscribe->wait_for_messages(1) while 1;

TODO: The final block here has not been tested.


=head1 DESCRIPTION

This role is supposed to be composed into a class along with a L<RDF::QueryX::Cache::Role::Predicter>.

=head2 Constructor

=over

=item C<< new(%attributes) >>

Moose-style constructor function.

=back

=head2 Attributes and methods

=cut


sub rewrite {
	my $self = shift;
	return RDF::Query->new($self->_translate($self->query->pattern));
}

sub _translate {
	my ($self, $a) = @_;
	Carp::confess "Not a reference? " . Dumper($a) unless blessed($a);
	if ($a->isa('RDF::Query::Algebra::Construct')) {
		return RDF::Query::Algebra::Construct->new($self->_translate($a->pattern), $a->triples);
	} elsif ($a->isa('RDF::Query::Algebra::Project')) {
		return $a;
	} elsif ($a->isa('RDF::Query::Algebra::GroupGraphPattern')) {
		my $ggp = RDF::Query::Algebra::GroupGraphPattern->new;
		foreach my $p ($a->patterns) {
			my @tps = $self->_translate($p);
			map { $ggp->add_pattern($_) } @tps;
		}
		return $ggp;
	} elsif ($a->isa('RDF::Query::Algebra::BasicGraphPattern')) {
		my @local;
		my @remote;
		foreach my $t ($a->triples) {
			my $key = $self->digest($t);
			if ($key && ($self->cache->is_valid($key))) {
				push (@local, $t);
			} else {
				push(@remote, $t);
			}
		}
		my @all;
		if (scalar @local > 0) {
			push(@all, RDF::Query::Algebra::BasicGraphPattern->new(@local));
		}
		if (scalar @remote > 0) {
			push(@all, RDF::Query::Algebra::Service->new(RDF::Query::Node::Resource->new($self->remoteendpoint),
																		RDF::Query::Algebra::GroupGraphPattern->new(RDF::Query::Algebra::BasicGraphPattern->new(@remote))));
		}
		return @all;
	}  elsif ($a->isa('RDF::Trine::Statement')) {
		return $a;
	} elsif ($a->isa('RDF::Query::Node')) {
		return $a;
#	} elsif ($a->isa('RDF::Query::Algebra::Limit')) {
#		return $a; # TODO: Support rewrite
#	} elsif ($a->isa('RDF::Query::Algebra::Offset')) {
#		return $a; # TODO: Support rewrite
#	} elsif ($a->isa('RDF::Query::Algebra::Path')) {
#		return $a; # TODO: Support rewrite
	} elsif ($a->isa('RDF::Query::Algebra::Filter')) {
		# TODO: Filters must be moved to their correct BGP
#		if ($a->pattern->isa('RDF::Query::Algebra::GroupGraphPattern')) {
#		} else {
			my $p = $self->_translate($a->pattern);
			return RDF::Query::Algebra::Filter->new($a->expr, $p);
#		}
	} elsif ($a->isa('RDF::Query::Expression')) {
		return $a;
		# TODO: Treat expressions to support EXISTS
	# } elsif ($a->isa('RDF::Query::Expression::Binary')) {
	# 	return $a;
	# } elsif ($a->isa('RDF::Query::Expression::Unary')) {
	# 	return $a;
	} elsif ($a->isa('RDF::Query::VariableBindings')) {
		return $a;
	} elsif ($a->isa('RDF::Query::Algebra::Table')) {
		return $a;
#	} elsif ($a->isa('RDF::Query::Algebra::Aggregate')) {
		# TODO: Support rewrite
#		return $a;
#	} elsif ($a->isa('RDF::Query::Algebra::Sort')) {
		# TODO: Support rewrite
#		return $a;
	} elsif ($a->isa('RDF::Query::Algebra::Distinct')
				|| $a->isa('RDF::Query::Algebra::Minus')
				|| $a->isa('RDF::Query::Algebra::Union')
				|| $a->isa('RDF::Query::Algebra::Optional')
				|| $a->isa('RDF::Query::Algebra::NamedGraph')
				|| $a->isa('RDF::Query::Algebra::Extend')) {
		return ref($a)->new(map { $self->_translate($_) } $a->construct_args);
	} #elsif ($a->isa('RDF::Query::Algebra::SubSelect')) {
		# TODO: Support rewrite; hard right now for the lack of feeding algebra back to query constructor
	   # return RDF::Query->new($self->_translate($a->query->patterns));
	else {
		Carp::confess "Unrecognized algebra " . ref($a);
	}
}

has _filters => (is => 'rw', isa => HashRef);

1;


=head1 AUTHOR

Kjetil Kjernsmo E<lt>kjetilk@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2015 by Kjetil Kjernsmo.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
