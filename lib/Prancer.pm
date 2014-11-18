package Prancer;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = "1.00";

use Cwd ();
use Module::Load ();
use Try::Tiny;
use Carp;

# this call implicitly makes Prancer a subclass of Web::Simple::Application
# this imports a number of things into our local namespace. see ->import below
# for more info on how this is handled.
use Web::Simple 'Prancer';

use Prancer::Config;
use Prancer::Request;
use Prancer::Response;

# even though this *should* work automatically, it was not
our @CARP_NOT = qw(Prancer Try::Tiny);

# the list of internal methods that will be exported
my @to_export = ();

sub new {
    my ($class, $configuration_file) = @_;
    my $self = bless({}, $class);

	# load configuration options
    $self->{'_config'} = Prancer::Config->load($configuration_file);

	# wrap imported methods
    for my $method (@to_export) {
        no strict 'refs';
        no warnings 'redefine';
        *{"${\$method->[0]}::${\$method->[1]}"} = sub {
            my $internal = "_${\$method->[1]}";
            &$internal($self, @_);
        };
    }

	# get the PSGI app from Web::Simple;
    my $app = $self->to_psgi_app();

	# enable static document loading
    $app = $self->_enable_static($app);

	# enable sessions
    $app = $self->_enable_sessions($app);

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
                croak "missing implementation of 'handler' in ${namespace}";
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

sub _enable_static {
    my ($self, $app) = @_;

    my $config = $self->{'_config'}->remove('static');
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
                'path' => sub { s!^$url!!x },
                'root' => $path,
                'pass_through' => 1,
            );
        } catch {
            my $error = (defined($_) ? $_ : "unknown");
            carp "initialization warning generated while trying to load the static file loader: ${error}";
        };
    }

    return $app;
}

sub _enable_sessions {
    my ($self, $app) = @_;

    my $config = $self->{'_config'}->remove('session');
    if ($config) {
        try {
            # load the session state module first
            # this will probably be a cookie
            my $state_module = undef;
            my $state_options = undef;
            if (ref($config->{'state'}) && ref($config->{'state'}) eq 'HASH') {
                $state_module = $config->{'state'}->{'driver'};
                $state_options = $config->{'state'}->{'options'};
            }

			# make sure state options are legit
            if (defined($state_options) && (!ref($state_options) || ref($state_options) ne 'HASH')) {
                die "session state configuration options are invalid -- expected a HASH\n";
            }

            # set defaults and then load the state module
            $state_options ||= {};
            $state_module ||= 'Prancer::Session::State::Cookie';
            Module::Load::load($state_module);

            # set the default for the session name because the plack
            # default is stupid
            $state_options->{'session_key'} ||= 'PSESSION';

            # load the store module second
            my $store_module = undef;
            my $store_options = undef;
            if (ref($config->{'store'}) && ref($config->{'store'}) eq 'HASH') {
                $store_module = $config->{'store'}->{'driver'};
                $store_options = $config->{'store'}->{'options'};
            }

			# make sure store options are legit
            if (defined($store_options) && (!ref($store_options) || ref($store_options) ne 'HASH')) {
                die "session store configuration options are invalid -- expected a HASH\n";
            }

            # set defaults and then load the store module
            $store_options ||= {};
            $store_module ||= 'Prancer::Session::Store::Memory';
            Module::Load::load($store_module);

            require Plack::Middleware::Session;
            $app = Plack::Middleware::Session->wrap($app,
                'state' => $state_module->new($state_options),
                'store' => $store_module->new($store_options),
            );
        } catch {
            my $error = (defined($_) ? $_ : "unknown");
            carp "initialization warning generated while trying to load the session handler: ${error}";
        };
    }

    return $app;
}

1;

=head1 NAME

Prancer

=head1 SYNOPSIS

TODO

=cut

