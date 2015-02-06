package RDF::QueryX::Cache::Role::Predicter::Naive;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(Int);

use RDF::Query;
use RDF::Query::Algebra qw(bgp triple);
use RDF::Trine qw(variable);
use URI::Escape::XS qw/uri_escape/;
use Scalar::Util qw(refaddr);
use Carp;

with 'RDF::QueryX::Cache::Role::Predicter';


=pod

=encoding utf-8

=head1 NAME

RDF::QueryX::Cache::Role::Predicter::Naive - A plugin for a naive predicter for SPARQL prefetching

=head1 SYNOPSIS

To compose this to a class, do e.g.:

  package MyPredicter;
  use Moo;
  with 'RDF::QueryX::Cache::Role::Predicter::Naive';

and then you can do for example:

   use Redis::Fast;
   my $redis = Redis::Fast->new;
  	my $naive = MyPredicter->new(query => RDF::Query->new('CONSTRUCT WHERE { ?foo a :Bar . }'),
						              cache => CHI->new( driver => 'Memory', global => 1 ),
					                 store => $redis,
						              remoteendpoint => 'http://localhost/');
   $naive->analyze;

Then, you can wait for queries to prefetch.

   use LWP::Simple;
   use Redis::Fast;
   my $subscribe = Redis::Fast->new;
   $subscribe->subscribe('prefetch.queries', &get);
   $subscribe->wait_for_messages(1) while 1;

TODO: The final block here has not been tested.


=head1 DESCRIPTION

This is a L<Moo::Role> that needs to be composed into a class to do
any real work. It implements the API found in
L<RDF::QueryX::Cache::Role::Predicter>. It is planned that the actual
classes that uses these roles are to have a plugin architecture, to
make it easy to write other predicter plugins.

This plugin simply looks for predicates that occur more than a certain
number of times.

=head2 Constructor

=over

=item C<< new(%attributes) >>

Moose-style constructor function.

=back

=head2 Attributes and methods

These attributes may be passed to the constructor to set them, or
called like methods to get them, see
L<RDF::QueryX::Cache::Role::Predicter> for other attributes.

=over

=item C<< digest >>

Will return the URI value of the predicate if present, or C<undef> if not.

=item C<< threshold >>

The number of times a predicate must occur to be legible for prefetching.

=item C<< analyze >>

Loops the triple patterns, checks if any of them have a cached result
(TODO) and increments the number of times a certain predicate has been
seen in the store. When that number exceeds the C<threshold>, a single
triple pattern query with that predicate is published to the Redis
store with topic C<prefetch.queries>.

=back

=cut

sub analyze {
	my $self = shift;
	my $qo = $self->query;
	my $count = 0;
	# TODO: Return undef if we can't process the query
	foreach my $quad ($qo->pattern->subpatterns_of_type('RDF::Trine::Statement')) {
		my $key = $self->digest($quad);

		# First, create the patterns used to evaluate the query
		if ($key && ($self->cache->is_valid($key))) {
			$self->add_localtriples($quad);
			$count++;
		} else {
			$self->add_remotetriples($quad);
		}

		next unless ($key);

		# Then, update the storage and push an event so that the cache manager can deal with prefetches
		$self->store->incr($key);
		my $count = $self->store->get($key);
		if ($count == $self->threshold) { # Fails if two clients are updating at the same time
			my $triple = RDF::Query::Algebra::Triple->new(variable('s'), $quad->predicate, variable('o'));
			$self->store->publish('prefetch.queries', $self->remoteendpoint . '?query=' . uri_escape('CONSTRUCT WHERE { ' . $triple->as_sparql . ' }'));
		}

	}
	return $count;
}

has threshold => ( is => 'rw', isa => Int, default => sub { 3 });


sub digest {
	my ($self, $quad) = @_;
	if ($quad->predicate->is_resource) {
		return $quad->predicate->uri_value;
	} else {
		return undef;
	}
}

sub rewrite {
	my $self = shift;
	my $newquery = $self->query;
	return $self->translate($newquery->pattern);
}

sub translate {
	my ($self, $a) = @_;
	Carp::confess "Not a reference? " . Dumper($a) unless blessed($a);
	if ($a->isa('RDF::Query::Algebra::Construct')) {
		return RDF::Query::Algebra::Construct->new($self->translate($a->pattern), $a->triples);
	} elsif ($a->isa('RDF::Query::Algebra::Project')) {
		return $a;
	} elsif ($a->isa('RDF::Query::Algebra::GroupGraphPattern')) {
		my $ggp = RDF::Query::Algebra::GroupGraphPattern->new;
		foreach my $p ($a->patterns) {
			my @tps = $self->translate($p);
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
																		RDF::Query::Algebra::BasicGraphPattern->new(@remote)));
		}
		return @all;
	}  elsif ($a->isa('RDF::Trine::Statement')) {
		return $a;
	} elsif ($a->isa('RDF::Query::Node')) {
		return $a;
	} elsif ($a->isa('RDF::Query::Algebra::Limit')) {
		return $a; # TODO: Support rewrite
	} elsif ($a->isa('RDF::Query::Algebra::Offset')) {
		return $a; # TODO: Support rewrite
	} elsif ($a->isa('RDF::Query::Algebra::Path')) {
		return $a; # TODO: Support rewrite
	} elsif ($a->isa('RDF::Query::Algebra::Filter')) {
		# TODO: Filters must be moved to their correct BGP
		my $p           = $self->translate($a->pattern);
		return RDF::Query::Algebra::Filter->new($a->expr, $p);
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
	} elsif ($a->isa('RDF::Query::Algebra::Aggregate')) {
		# TODO: Support rewrite
		# my $p           = $self->translate($a->pattern);
		# my @group;
		# foreach my $g ($a->groupby) {
		# 	if ($g->isa('RDF::Query::Expression::Alias')) {
		# 		my $var         = $self->translate($g->alias);
		# 		my $varexpr     = $self->translate_expr($g->alias);
		# 		push(@group, $varexpr);
		# 		my $expr        = $self->translate_expr( $g->expression );
		# 		$p      = Attean::Algebra::Extend->new( children => [$p], variable => $var, expression => $expr );
		# 	} else {
		# 		push(@group, $self->translate_expr($g));
		# 	}
		# }
		# my @ops         = $a->ops;
		
		# my @aggs;
		# foreach my $o (@ops) {
		# 	my ($str, $op, $scalar_vars, @vars)     = @$o;
		# 	my $operands    = [map { $self->translate_expr($_) } grep { blessed($_) } @vars];
		# 	my $distinct    = ($op =~ /-DISTINCT$/);
		# 	$op                             =~ s/-DISTINCT$//;
		# 	my $expr        = Attean::AggregateExpression->new(
		# 																		distinct        => $distinct,
		# 																		operator        => $op,
		# 																		children        => $operands,
		# 																		scalar_vars     => $scalar_vars,
		# 																		variable        => variable(".$str"),
		# 																	  );
		# 	push(@aggs, $expr);
		# }
		# return Attean::Algebra::Group->new(
		# 											  children        => [$p],
		# 											  groupby         => \@group,
		# 											  aggregates      => \@aggs,
		# 											 );
		return $a;
	} elsif ($a->isa('RDF::Query::Algebra::Sort')) {
		# TODO: Support rewrite
		# my $p           = $self->translate($a->pattern);
		# my @order       = $a->orderby;
		# my @cmps;
		# foreach my $o (@order) {
		# 	my ($dir, $e)   = @$o;
		# 	my $asc                         = ($dir eq 'ASC');
		# 	my $expr                        = $self->translate_expr($e);
		# 	push(@cmps, Attean::Algebra::Comparator->new(ascending => $asc, expression => $expr));
		# }
		# return Attean::Algebra::OrderBy->new( children => [$p], comparators => \@cmps );
		return $a;
	} elsif ($a->isa('RDF::Query::Algebra::Distinct')
				|| $a->isa('RDF::Query::Algebra::Minus')
				|| $a->isa('RDF::Query::Algebra::Union')
				|| $a->isa('RDF::Query::Algebra::Optional')
				|| $a->isa('RDF::Query::Algebra::NamedGraph')
				|| $a->isa('RDF::Query::Algebra::Extend')) {
		return ref($a)->new(map { $self->translate($_) } $a->construct_args);
	} #elsif ($a->isa('RDF::Query::Algebra::SubSelect')) {
		# TODO: Support rewrite; hard right now for the lack of feeding algebra back to query constructor
	   # return RDF::Query->new($self->translate($a->query->patterns));
	else {
		Carp::confess "Unrecognized algebra " . ref($a);
	}
}


1;


=head1 AUTHOR

Kjetil Kjernsmo E<lt>kjetilk@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2015 by Kjetil Kjernsmo.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
