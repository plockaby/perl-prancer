package Prancer;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = "1.00";

use Exporter;
use parent qw(Exporter);

our @EXPORT_OK = qw(config logger);
our %EXPORT_TAGS = ('all' => [ @EXPORT_OK ]);

use Carp;
use Module::Load ();
use Storable qw(dclone);
use Try::Tiny;

use Prancer::Config;
use Prancer::Logger;
use Prancer::Request;
use Prancer::Response;
use Prancer::Context;

sub new {
    my ($class, $config_path, $handler, @args) = @_;

    # already got an object
    return $class if ref($class);

    # this is a singleton
    my $instance = undef;
    {
        no strict 'refs';
        $instance = \${"$class\::_instance"};
        return $$instance if defined($$instance);
    }

    my $self = bless({
        '_handler' => $handler,    # the name of the class that will implement the handler
        '_handler_args' => \@args, # any arguments that should be passed to the handler on creation
    }, $class);

    # load configuration
    $self->{'_config'} = Prancer::Config->load($config_path);

    # load the configured logger
    $self->{'_logger'} = Prancer::Logger->load($self->{'_config'}->{'logger'});

    $$instance = $self;
    return $self;
}

# return an already created instance of ourselves or croak if one doesn't exist
sub instance {
    my $class = __PACKAGE__;

    {
        no strict 'refs';
        my $instance = \${"$class\::_instance"};
        return $$instance if defined($$instance);
    }

    croak "must create an instance of " . __PACKAGE__ . " before it may be used";
}

sub run {
    my $self = shift;

    try {
        Module::Load::load($self->{'_handler'});
    } catch {
        logger->fatal("could not initialize handler: " . (defined($_) ? $_ : "unknown"));
        croak;
    };

    my $app = sub {
        my $env = shift;

        # create a context to pass to the request
        my $context = Prancer::Context->new(
            'env'      => $env,
            'request'  => Prancer::Request->new($env),
            'response' => Prancer::Response->new($env),
        );

        my $handler = $self->{'_handler'};
        my $copy = $handler->new($context, @{$self->{'_handler_args'}});
        return $copy->handle($env);
    };

    # capture warnings and logging messages and send them to the configured logger
    require Prancer::Middleware::Logger;
    $app = Prancer::Middleware::Logger->wrap($app);

    # serve up static files if configured to do so
    $app = $self->_enable_static($app);

    return $app;
}

sub logger {
    my $self = instance();
    return $self->{'_logger'};
}

sub config {
    my $self = instance();
    my %args = (
        'has' => undef,
        'get' => undef,
        'set' => undef,
        'value' => undef,
        'remove' => undef,
        @_,
    );

    if (defined($args{'remove'})) {
        return delete($self->{'_config'}->{$args{'remove'}});
    }

    if (defined($args{'has'})) {
        return exists($self->{'_config'}->{$args{'has'}});
    }

    if (defined($args{'set'})) {
        my $old = undef;

        # only bother returning a value if the method was called in a non-void context
        $old = config(get => $args{'set'}) if defined(wantarray());

        if (ref($args{'value'})) {
            # clone the value we were given to avoid inadvertently modifying
            # the configuration through references
            $self->{'_config'}->{$args{'set'}} = dclone($args{'value'});
        } else {
            # can't clone non-references
            $self->{'_config'}->{$args{'set'}} = $args{'value'};
        }

        return $old;
    }

    if (defined($args{'get'})) {
        # only bother returning a value if the method was called in a non-void context
        if (defined(wantarray()) && defined($self->{'_config'}->{$args{'get'}})) {
            # clone to avoid inadvertently changing values through references
            my $value = $self->{'_config'}->{$args{'get'}};
            return dclone($value) if ref($value);
            return $value;
        }
    }

    return;
}

sub _enable_static {
    my ($self, $app) = @_;

    my $config = config(get => 'static');
    if ($config) {
        try {
            # this intercepts requests for /static/* and checks to see if
            # the requested file exists in the configured path. if it does
            # it is served up. if it doesn't then the request will pass
            # through to the handler.
            my $path = Cwd::realpath($config->{'path'});
            die "no path is defined\n" unless defined($path) && $path;
            die "${path} does not exist\n" unless (-e $path);
            die "${path} is not a directory\n" unless (-d $path);
            die "${path} is not readable\n" unless (-r $path);

            require Plack::Middleware::Static;
            $app = Plack::Middleware::Static->wrap($app,
                'path' => sub { s!^/static/!!x },
                'root' => $path,
                'pass_through' => 1,
            );
            logger->info("serving static files from ${path} at /static");
        } catch {
            logger->warn("could not initialize static file loader: initialization error: $_");
        };
    } else {
        logger->warn("could not initialize static file loader: not configured");
    }

    return $app;
}

1;

=head1 NAME

Prancer - Another PSGI Framework

=head1 SYNOPSIS

Prancer is yet another PSGI framework. This one is designed to be a bit smaller
and out of the way than others but it could probably be described best as
project derived from L<NIH syndrome|https://en.wikipedia.org/wiki/Not_Invented_Here>.

Here's how it might be used:

    ==> myapp.psgi

    use Prancer;
    my $app = Prancer->new("/path/to/confdir", "MyApp");
    $app->run();

    ==> MyApp.pm

    package MyApp;

    use Prancer::Application qw(:all);
    use parent qw(Prancer::Application);

    sub handle {
        my $self = shift;

        mount('GET', '/', sub {
            context->header(set => 'Content-Type', value => 'text/plain');
            context->body("hello world");
            context->finalize(200);
        });

        return dispatch;
    }

Full documentation can be found in L<Prancer::Manual>.

=head1 INSTALLATION

To install this module, run the following commands:

    perl Makefile.PL
    make
    make test
    make install

If this ever makes it to CPAN you can install it with this simple command:

    perl -MCPAN -e 'install Dancer2'

=head1 METHODS

With the exception of C<-E<gt>new> and C<-E<gt>run>, all methods should be
called in a static context. Additionally, with the same exception, all methods
are exportable individually or with C<qw(:all)>.

=over 4

=item ->new CONFIG PACKAGE ARGS

This will create your application. It takes two arguments:

=over 4

=item CONFIG

This a path to a directory containing configuration files. How configuration
files are loaded is detailed below.

=item PACKAGE

This is the name of a package that implements your application. The package
named should extend L<Prancer::Application> though this is not enforced.

=item ARGS

After the name of the package, any number of arguments may be added. Any extra
arguments are passed directly to the C<new> method on the named package when it
is created for a request.

=back

=item ->run

This starts your application. It takes no arguments.

=item logger

This gives access to the logger. For example:

    logger->info("Hello");
    logger->fatal("uh oh");
    logger->debug("here we are");

=item config

This gives access to the configuration. For example:

    config(has => 'foo');
    config(get => 'foo');
    config(set => 'foo', value => 'bar');
    config(remove => 'foo');

Any changes to the configuration do not persist back to the actual
configuration file. Additionally they do not persist between threads or
processes.

Whenever this method is used to get a configuration option and that option
is reference, the reference will be cloned by Storable to prevent changes to
one copy from affecting other uses. But this could have performance
implications if you are routinely getting large data structures out if your
configuration files.

=back

=head1 CONFIGURATION

One doesn't need to create any configuration to use Prancer but then Prancer
wouldn't be very useful. Prancer uses L<Config::Any> to process configuration
files so anything supported by that will be supported by this. It will load
configuration files from given path set when your application initialized.
First it will look for a file named C<config.ext> where C<ext> is something
like C<yml> or C<ini>. Then it will look for a file named after the current
environment like C<develoment.ext> or C<production.ext>. The environment is
derived by looking first for an environment variable called C<ENVIRONMENT>,
then for an environment variable called C<PLACK_ENV>. If neither of those exist
then the default is C<development>. Configuration files will be merged such
that the environment configuration file will take precedence over the global
configuration file.

Arbitrary configuration directives can be put into your configuration files
and they can be accessed like this:

    config(get => 'foo');

The configuration accessors will only give you configuration directives found
at the root of the configuration file. So if you use any data structures you
will have to decode them yourself. For example, if you create a YAML file like
this:

    foo:
        bar1: asdf
        bar2: fdsa

Then you will only be able to get the value to C<bar1> like this:

    my $foo = config(get => 'foo')->{'bar1'};

=head2 Reserved Configuration Options

To support the components of Prancer, these keys are used:

=over 4

=item logger

Configures the logging system. For example:

    logger:
        driver: Prancer::Logger::Console
        options:
            level: debug

=item static

Configures a directory where static documents can be found and served using
L<Plack::Middleware::Static>. For example:

    static:
        path: /srv/www/site/static

The only configuration option for static documents is C<path>. If this path
is not defined your application will not start. If this path does not point
to a directory that is readable your application will not start.

=back

=head1 CREDITS

Large portions of this library were taken from the following locations and
projects:

=over 4

=item

HTTP status code documentation taken from L<Wikipedia|http://www.wikipedia.org>.

=item

L<Prancer::Config> is derived directly from L<Dancer2::Core::Role::Config>.
Thank you to the L<Dancer2|https://github.com/PerlDancer/Dancer2> team.

=item

L<Prancer::Request>, L<Prancer::Request::Upload> and L<Prancer::Response> are
but thin wrappers to and reimplementations of L<Plack::Request>,
L<Plack::Request::Upload> and L<Prancer::Response>. Thank you to Tatsuhiko
Miyagawa.

=back

=head1 COPYRIGHT

Copyright 2013, 2014 Paul Lockaby. All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
