use 5.010001;
use strict;
use warnings;

package RDF::QueryX::Cache;

our $AUTHORITY = 'cpan:KJETILK';
our $VERSION   = '0.001_01';
use parent qw( Plack::Component );
use Plack::Request;
use RDF::Query;
use RDF::Trine;
use RDF::Trine::Parser;
use Try::Tiny;
use Encode;
use CHI;
use Redis::Fast;
use RDF::QueryX::Cache::QueryProcessor;
use LWP::UserAgent;
use Plack::Response;
use Log::Log4perl ':easy';
use Log::Contextual qw( :log ), -package_logger => Log::Log4perl->get_logger;

BEGIN {
#	if ($ENV{TEST_VERBOSE}) {
		Log::Log4perl->easy_init( { level   => $TRACE,
											 category => 'RDF.QueryX.Cache' 
										  } );
#	} else {
#		Log::Log4perl->easy_init( { level   => $FATAL,
#											 category => 'RDF.LinkedData' 
#										  } );
#	}
	use Log::Contextual -logger => Log::Log4perl->get_logger;
}

sub prepare_app {
	# TODO: Use a config system
	my $self = shift;
	$self->{baseconfig} = {
								  cache => CHI->new( driver => 'Redis', namespace =>'cache' ),
								  store => Redis::Fast->new()
								 };
}

sub call {
    my($self, $env) = @_;
	 my $req = Plack::Request->new($env);
	 my $query = RDF::Query->new($req->parameters->get('query'));
	 unless ($query) {
		 log_debug {'No query was found as parameter, forwarding the whole request'};
		 my $response = _forward_request($req);
		 return $response->finalize;
	 }
	 log_trace{'Found query: ' . $query->as_sparql};
	 my $req_uri = $req->uri;
	 my $remoteendpoint = $req_uri->scheme . '://' . $req_uri->host . $req_uri->path;
	 my $process = RDF::QueryX::Cache::QueryProcessor->new(query => $query,
																			 remoteendpoint => $remoteendpoint,
																			 %{$self->{baseconfig}});

	 unless ($process->analyze) { # Examine the query and schedule prefetcher
		 log_debug {'Analysis of the query found no cached patterns, forwarding the whole request'};
		 my $response = _forward_request($req);
		 return $response->finalize;
	 }

	 my $newquery;
	 try {
		 $newquery = $process->rewrite; # Rewrite with SERVICE
	 } catch {
		 log_info {"Could not rewrite, because $_"};
		 my $response = _forward_request($req);
		 return $response->finalize;
	 }
	 # TODO: Need more efficient parsing and loading
	 my $model = RDF::Trine::Model->temporary_model;
	 my $parser = RDF::Trine::Parser->new( 'turtle' );
	 foreach my $key ($process->all_local_keys) {
		 my $cacheres = $process->cache->get($key);
		 $parser->parse_into_model('', $cacheres->decoded_content, $model);
	 }
	 log_debug {'Cached data loaded'};
	 my $iter = $newquery->execute($model);
	 my $response = Plack::Response->new;
	 my ($ct, $s);
	 try {
		 ($ct, $s) = RDF::Trine::Serializer->negotiate('request_headers' => $req->headers);
	 } catch {
		 $response->status(406);
		 $response->headers->content_type('text/plain');
		 $response->body('HTTP 406: No serialization available any specified content type');
		 return $response;
	 };

	 $response->status(200);
	 $response->headers->header('Vary' => join(", ", qw(Accept)));
	 my $body = $s->serialize_iterator_to_string($iter);
	 $response->headers->content_type($ct);
	 $response->body(encode_utf8($body));
	 # TODO: Preserve remote host headers
	 # TODO: Add Age, Via should probably happen here
	 log_debug {'Returning response'};
    return $response->finalize;
}

sub _forward_request {
	my $req = shift;
	my $ua = LWP::UserAgent->new;
	my $fres = $ua->request(HTTP::Request->new($req->method, $req->uri, $req->headers, $req->content));
	# TODO: insert Via
	my $response = Plack::Response->new;
	$response->status($fres->code);
	$response->headers($fres->headers);
	$response->body($fres->content);
	return $response;
}


1;

__END__

=pod

=encoding utf-8

=head1 NAME

RDF::QueryX::Cache - A research module to manage SPARQL query caching on a proxy

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 BUGS

Please report any bugs to
L<https://github.com/kjetilk/p5-rdf-queryx-cache/issues>.

=head1 SEE ALSO

=head1 AUTHOR

Kjetil Kjernsmo E<lt>kjetilk@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2015 by Kjetil Kjernsmo.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.


=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

