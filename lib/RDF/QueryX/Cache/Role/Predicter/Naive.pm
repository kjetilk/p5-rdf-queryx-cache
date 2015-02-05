package RDF::QueryX::Cache::Role::Predicter::Naive;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(Int);

use RDF::Query qw(bgp triple);
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
	warn "FOOOO: " . Dumper($self->translate($newquery->pattern));
}

sub translate {
	my ($self, $a) = @_;
	if ($a->isa('RDF::Query::Algebra::Construct')) {
		my $p           = $self->translate($a->pattern);
		my @triples     = @{ $a->triples || [] };
		if (scalar(@triples) == 1 and $triples[0]->isa('RDF::Query::Algebra::BasicGraphPattern')) {
			@triples        = $triples[0]->triples;
		}
		return Attean::Algebra::Construct->new( children => [$p], triples => [map { $self->translate($_) } @triples] );
	} elsif ($a->isa('RDF::Query::Algebra::Project')) {
		my $p   = $a->pattern;
		my $v   = $a->vars;
		my @vars        = map { variable($_->name) } @$v;
		return Attean::Algebra::Project->new(
														 children        => [ $self->translate($p) ],
														 variables       => [ @vars ],
														);
	} elsif ($a->isa('RDF::Query::Algebra::GroupGraphPattern')) {
		my @p   = map { $self->translate($_) } $a->patterns;
		if (scalar(@p) == 0) {
			return Attean::Algebra::BGP->new();
		} else {
			while (scalar(@p) > 1) {
				my ($l, $r)     = splice(@p, 0, 2);
				unshift(@p, Attean::Algebra::Join->new( children => [$l, $r] ));
			}
			return shift(@p);
		}
	} elsif ($a->isa('RDF::Query::Algebra::BasicGraphPattern')) {
		warn "DAAAAAAAAAAHut";
		my @p;
		foreach my $t ($a->triples) {
			if ($t->subject->is_variable) {
				$t = triple(variable('s'), $t->predicate, $t->object);
			}
			push(@p, $t);
		}
		return bgp(@p);
	}  elsif ($a->isa('RDF::Query::Algebra::Triple')) {
		my @nodes       = map { $self->translate($_) } $a->nodes;
		return Attean::TriplePattern->new(@nodes);
	} elsif ($a->isa('RDF::Query::Node::Variable')) {
		my $value       = variable($a->isa("RDF::Query::Node::Variable::ExpressionProxy") ? ("." . $a->name) : $a->name);
		$value          = Attean::ValueExpression->new(value => $value) if ($self->in_expr);
		return $value;
	} elsif ($a->isa('RDF::Query::Node::Resource')) {
		my $value       = iri($a->uri_value);
		$value          = Attean::ValueExpression->new(value => $value) if ($self->in_expr);
		return $value;
	} elsif ($a->isa('RDF::Query::Node::Blank')) {
		my $value       = blank($a->blank_identifier);
		$value          = Attean::ValueExpression->new(value => $value) if ($self->in_expr);
		return $value;
	} elsif ($a->isa('RDF::Query::Node::Literal')) {
		my $value;
		if ($a->has_language) {
			$value  = langliteral($a->literal_value, $a->literal_value_language);
		} elsif ($a->has_datatype) {
			$value  = dtliteral($a->literal_value, $a->literal_datatype);
		} else {
			$value  = literal($a->literal_value);
		}
		$value  = Attean::ValueExpression->new(value => $value) if ($self->in_expr);
		return $value;
	} elsif ($a->isa('RDF::Query::Algebra::Limit')) {
		my $child       = $a->pattern;
		if ($child->isa('RDF::Query::Algebra::Offset')) {
			my $p   = $self->translate($child->pattern);
			return Attean::Algebra::Slice->new( children => [$p], limit => $a->limit, offset => $child->offset );
		} else {
			my $p   = $self->translate($child);
			return Attean::Algebra::Slice->new( children => [$p], limit => $a->limit );
		}
	} elsif ($a->isa('RDF::Query::Algebra::Offset')) {
		my $p   = $self->translate($a->pattern);
		return Attean::Algebra::Slice->new( children => [$p], offset => $a->offset );
	} elsif ($a->isa('RDF::Query::Algebra::Path')) {
		my $s           = $self->translate($a->start);
		my $o           = $self->translate($a->end);
		my $path        = $self->translate_path($a->path);
		return Attean::Algebra::Path->new( subject => $s, path => $path, object => $o );
	} elsif ($a->isa('RDF::Query::Algebra::NamedGraph')) {
		my $graph       = $self->translate($a->graph);
		my $p           = $self->translate($a->pattern);
		return Attean::Algebra::Graph->new( children => [$p], graph => $graph );
	} elsif ($a->isa('RDF::Query::Algebra::Filter')) {
		my $p           = $self->translate($a->pattern);
		my $expr        = $self->translate_expr($a->expr);
		return Attean::Algebra::Filter->new( children => [$p], expression => $expr );
	} elsif ($a->isa('RDF::Query::Expression::Binary')) {
		my $op  = $a->op;
		$op             = '=' if ($op eq '==');
		my @ops = $a->operands;
		my @operands    = map { $self->translate($_) } @ops;
		my $expr        = Attean::BinaryExpression->new( operator => $op, children => \@operands );
		return $expr;
	} elsif ($a->isa('RDF::Query::Expression::Unary')) {
		my $op  = $a->op;
		$op             = '=' if ($op eq '==');
		my ($child)     = $a->operands;
		my $expr        = Attean::UnaryExpression->new( operator => $op, children => [$self->translate($child)] );
		return $expr;
	} elsif ($a->isa('RDF::Query::Algebra::Extend')) {
		my $p           = $self->translate($a->pattern);
		my $vars        = $a->vars;
		foreach my $v (@$vars) {
			if ($v->isa('RDF::Query::Expression::Alias')) {
				my $var         = variable($v->name);
				my $expr        = $v->expression;
				$p      = Attean::Algebra::Extend->new( children => [$p], variable => $var, expression => $self->translate_expr( $expr ) );
			} else {
				die "Unexpected extend expression: " . Dumper($v);
			}
		}
		return $p;
	} elsif ($a->isa('RDF::Query::VariableBindings')) {
		my %bindings;
		foreach my $v ($a->variables) {
			if (my $term = $a->{ $v }) {
				$bindings{ $v } = $self->translate( $term );
			}
		}
		return Attean::Result->new( bindings => \%bindings );
	} elsif ($a->isa('RDF::Query::Algebra::Table')) {
		my @vars        = map { variable($_) } $a->variables;
		my @rows        = map { $self->translate($_) } $a->rows;
		return Attean::Algebra::Table->new( variables => \@vars, rows => \@rows );
	} elsif ($a->isa('RDF::Query::Algebra::Aggregate')) {
		my $p           = $self->translate($a->pattern);
		my @group;
		foreach my $g ($a->groupby) {
			if ($g->isa('RDF::Query::Expression::Alias')) {
				my $var         = $self->translate($g->alias);
				my $varexpr     = $self->translate_expr($g->alias);
				push(@group, $varexpr);
				my $expr        = $self->translate_expr( $g->expression );
				$p      = Attean::Algebra::Extend->new( children => [$p], variable => $var, expression => $expr );
			} else {
				push(@group, $self->translate_expr($g));
			}
		}
		my @ops         = $a->ops;
		
		my @aggs;
		foreach my $o (@ops) {
			my ($str, $op, $scalar_vars, @vars)     = @$o;
			my $operands    = [map { $self->translate_expr($_) } grep { blessed($_) } @vars];
			my $distinct    = ($op =~ /-DISTINCT$/);
			$op                             =~ s/-DISTINCT$//;
			my $expr        = Attean::AggregateExpression->new(
																				distinct        => $distinct,
																				operator        => $op,
																				children        => $operands,
																				scalar_vars     => $scalar_vars,
																				variable        => variable(".$str"),
																			  );
			push(@aggs, $expr);
		}
		return Attean::Algebra::Group->new(
													  children        => [$p],
													  groupby         => \@group,
													  aggregates      => \@aggs,
													 );
                } elsif ($a->isa('RDF::Query::Algebra::Sort')) {
						 my $p           = $self->translate($a->pattern);
						 my @order       = $a->orderby;
						 my @cmps;
						 foreach my $o (@order) {
							 my ($dir, $e)   = @$o;
							 my $asc                         = ($dir eq 'ASC');
							 my $expr                        = $self->translate_expr($e);
							 push(@cmps, Attean::Algebra::Comparator->new(ascending => $asc, expression => $expr));
						 }
						 return Attean::Algebra::OrderBy->new( children => [$p], comparators => \@cmps );
                } elsif ($a->isa('RDF::Query::Algebra::Distinct')) {
						 my $p           = $self->translate($a->pattern);
						 return Attean::Algebra::Distinct->new( children => [$p] );
                } elsif ($a->isa('RDF::Query::Algebra::Minus')) {
						 my $p           = $self->translate($a->pattern);
						 my $m           = $self->translate($a->minus);
						 return Attean::Algebra::Minus->new( children => [$p, $m] );
                } elsif ($a->isa('RDF::Query::Algebra::Union')) {
						 my @p           = map { $self->translate($_) } $a->patterns;
						 return Attean::Algebra::Union->new( children => \@p );
                } elsif ($a->isa('RDF::Query::Algebra::Optional')) {
						 my $p           = $self->translate($a->pattern);
						 my $o           = $self->translate($a->optional);
						 return Attean::Algebra::LeftJoin->new( children => [$p, $o] );
                } elsif ($a->isa('RDF::Query::Algebra::SubSelect')) {
						 my $q   = $a->query;
						 my $p   = $self->translate_query($q);
                        return $p;
                } elsif ($a->isa('RDF::Query::Expression::Function')) {
						 my $uri         = $a->uri->uri_value;
						 my @args        = map { $self->translate_expr($_) } $a->arguments;
						 if ($uri eq 'sparql:logical-and') {
							 my $algebra     = Attean::BinaryExpression->new( operator => '&&', children => [splice(@args, 0, 2)] );
							 while (scalar(@args)) {
								 $algebra        = Attean::BinaryExpression->new( operator => '&&', children => [$algebra, shift(@args)] );
							 }
							 return $algebra;
						 } elsif ($uri eq 'sparql:logical-or') {
							 my $algebra     = Attean::BinaryExpression->new( operator => '||', children => [splice(@args, 0, 2)] );
							 while (scalar(@args)) {
								 $algebra        = Attean::BinaryExpression->new( operator => '||', children => [$algebra, shift(@args)] );
                                }
							 return $algebra;
						 } elsif ($uri =~ /^sparql:(.+)$/) {
							 if ($1 eq 'exists') {
								 # re-translate the pattern as a pattern, not an expression:
								 my ($p) = map { $self->translate_pattern($_) } $a->arguments;
								 return Attean::ExistsExpression->new( pattern => $p );
							 } else {
								 return Attean::FunctionExpression->new( children => \@args, operator => $1, ($self->has_base ? (base => $self->base) : ()) );
							 }
						 } elsif ($uri =~ m<^http://www[.]w3[.]org/2001/XMLSchema#(?<cast>integer|decimal|float|double|string|boolean|dateTime)$>) {
							 my $cast        = $+{cast};
							 if ($cast =~ /^(?:integer|decimal|float|double)$/) {
								 return Attean::CastExpression->new( children => \@args, datatype => iri($uri) );
							 } elsif ($cast eq 'string') {
								 return Attean::FunctionExpression->new( children => \@args, operator => 'STR', ($self->has_base ? (base => $self->base) : ()) );
							 } elsif ($cast eq 'boolean') {
								 
							 } elsif ($cast eq 'dateTime') {
								 
							 }
						 }
						 warn "Unrecognized function: " . Dumper($uri, \@args);
                }
	Carp::confess "Unrecognized algebra " . ref($a);
}
}

}


1;


=head1 AUTHOR

Kjetil Kjernsmo E<lt>kjetilk@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2015 by Kjetil Kjernsmo.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
