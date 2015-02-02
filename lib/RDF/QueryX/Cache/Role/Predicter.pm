package RDF::QueryX::Cache::Role::Predicter;

use strict;
use warnings;

use Moo::Role;
use Types::Standard qw(InstanceOf Str Int ArrayRef);
use MooX::HandlesVia;
use Scalar::Util qw(blessed);

use RDF::Query;

has query => (is => 'ro', 
				  isa => InstanceOf['RDF::Query'],
				  required => 1
				 );

has remoteendpoint => (is => 'ro', isa => Str, required => 1);


has store => (is => 'ro',
				  isa => InstanceOf['Redis::Fast'],
				  required => 1
				 );

has pubsub => (is => 'ro',
				  isa => InstanceOf['Redis::Fast'],
				  required => 1
				 );

has cache => (is => 'ro',
				  isa => InstanceOf['CHI::Driver'],
				  required => 1
				 );

has localtriples => (is => 'rw',
							isa => ArrayRef,
							handles_via => 'Array',
							handles => {
											add_localtriples => 'push' 
										  },
							default => sub {[]});

has remotetriples => (is => 'rw',
							 isa => ArrayRef,
							 handles_via => 'Array',
							 handles => {
											 add_remotetriples => 'push' 
											},
							 default => sub {[]});


requires 'digest';
requires 'threshold';
requires 'analyze';

1;
