#!/usr/bin/perl

use strict;
use warnings;
use RDF::QueryX::Cache;
use Plack::Builder;

my $querycache = RDF::QueryX::Cache->new->to_app;

builder {
	$querycache
};
