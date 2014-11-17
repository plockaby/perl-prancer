package Prancer;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = "1.00";

use Cwd ();
use Try::Tiny;
use Web::Simple 'Prancer';

use Prancer::Config;
use Prancer::Request;
use Prancer::Response;

# the list of internal methods that will be exported
my @to_export = ();

sub new {
	my ($class, $configuration_file) = @_;
    my $self = bless({}, $class);
    my $app = $self->to_psgi_app();

	# load configuration options
    $self->{'_config'} = Prancer::Config->load($configuration_file);

    # NOTE: you can wrap Plack::Middleware things in here

	# enable sessions
    # TODO

	# enable static document loading
    $app = $self->_enable_static($app);

	# wrap imported methods
	for my $method (@to_export) {
        no strict 'refs';
        no warnings 'redefine';
        *{"${\$method->[0]}::${\$method->[1]}"} = sub {
            my $internal = "_${\$method->[1]}";
            &$internal($self, @_);
        };
	}

    return $app;
}

sub import {
    my ($class, @options) = @_;

	# store what namespace are importing things to
	my $namespace = caller(0);

    my @actions = ();
    for my $option (@options) {
        if ($option eq ':handler') {
            # this block makes our caller a child class of this class
            no strict 'refs';
            unshift(@{"${namespace}::ISA"}, __PACKAGE__);

            # this block ensures that the handler method is overridden in any
            # children classes by dying if it isn't.
            no warnings 'redefine';
            my $exported = __PACKAGE__ . "::handler";
            *{"${exported}"} = sub {
                die "missing implementation of 'handler' in ${namespace}\n";
            };
        }

		# these keywords will be exported as proxies to the real methods
		if ($option =~ /^(config)$/x) {
			# need to predefine it so that barewords work
			no strict 'refs';
			*{"${namespace}::${1}"} = sub {};

			# this will establish the actual method in ->new()
			push(@to_export, [ $namespace, $1 ]);
		}
    }

	# this is used by Web::Simple to not complain about keywords in prototypes
	# like HEAD and GET. but we need to extend it to classes that implement us
	# so we're adding it here.
    warnings::illegalproto->unimport();

    return;
}

# NOTE: your program can definitely implement ->dispatch_request instead of
# ->handler but ->handler will give you easier access to request and response
# data using Prancer::Request and Prancer::Response.
sub dispatch_request {
	my ($self, $env) = @_;

	my $request = Prancer::Request->new($env);
	my $response = Prancer::Response->new($env);
	my $session = undef;

    return $self->handler($env, $request, $response, $session);
}

## no critic (ProhibitUnusedPrivateSubroutines)
sub _config {
	my $self = shift;
	return $self->{'_config'};
}

sub _enable_sessions {
	# TODO
}

sub _enable_static {
    my ($self, $app) = @_;

    my $config = $self->_config->remove('static');
    if ($config) {
        try {
            # this intercepts requests for documents under the configured URL
            # and checks to see if the requested file exists in the configured
            # file system path. if it does exist then it is served up. if it
            # doesn't exist then the request will pass through to the handler.
            die "no url is configured for the static file loader\n" unless defined($config->{'url'});
            my $url = $config->{'url'};
			die "no path is configured for the static file loader\n" unless defined($config->{'path'});
            my $path = Cwd::realpath($config->{'path'});
            die $config->{'path'} . " does not exist\n" unless defined($path);
            die $config->{'path'} . " is not readable\n" unless (-r $path);

            require Plack::Middleware::Static;
            $app = Plack::Middleware::Static->wrap($app,
                'path' => sub { s!^/$url/!!x },
                'root' => $path,
                'pass_through' => 1,
            );
        } catch {
        	warn "could not initialize static file loader: initialization error: ${_}\n";
        };
    }

    return $app;
}

1;
