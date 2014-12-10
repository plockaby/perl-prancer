package Prancer;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = '1.00';

# using Web::Simple in this context will implicitly make Prancer a subclass of
# Web::Simple::Application. that will cause a number of things to be imported
# into the Prancer namespace. see ->import below for more details.
use Web::Simple 'Prancer';

use Try::Tiny;
use Carp;

use Prancer::Core;
use Prancer::Request;
use Prancer::Response;
use Prancer::Session;

# even though this *should* work automatically, it was not
our @CARP_NOT = qw(Prancer Try::Tiny);

# this is a list of methods that will be created on the fly and linked to
# private methods of the same name and only implemented in ourselves. this
# makes things like "$app->config()" work.
our @EXPORT_OK = qw(config);

# the list of methods that will be created on the fly, linked to private
# methods of the same name, and exported to the caller. this makes things
# like the bareword call to "config" work. this list is populated in ->import
our @TO_EXPORT = ();

sub new {
    my ($class, $configuration_file) = @_;
    my $self = bless({}, $class);

    # the core is where our methods *really* live
    # we mostly just proxy through to that
    $self->{'_core'} = Prancer::Core->new($configuration_file);

    # @TO_EXPORT is an array of arrayrefs representing methods that we want to
    # make available in our caller's namespace. each arrayref has two values:
    #
    #   0 = namespace into which we'll import the method
    #   1 = the method that will be imported (must be implemented in Prancer::Core)
    #
    # this makes "namespace::method" resolve to "$self->{'_core'}->method()".
    for my $method (@TO_EXPORT) {
        # don't import things that can't be resolved
        croak "Prancer::Core does not implement ${\$method->[1]}" unless $self->{'_core'}->can($method->[1]);

        no strict 'refs';
        no warnings 'redefine';
        *{"${\$method->[0]}::${\$method->[1]}"} = sub {
            my $internal = "${\$method->[1]}";
            return $self->{'_core'}->$internal(@_);
        };
    }

    # here are things that will always be exported into the Prancer namespace.
    for my $method (@EXPORT_OK) {
        # don't import things that can't be resolved
        croak "Prancer::Core does not implement ${\$method->[1]}" unless $self->{'_core'}->can($method);

        no strict 'refs';
        no warnings 'redefine';
        *{"${\__PACKAGE__}::${method}"} = sub {
            return $self->{'_core'}->$method(@_);
        };
    }

    $self->initialize();
    return $self;
}

sub import {
    my ($class, @options) = @_;

    # store what namespace are importing things to
    my $namespace = caller(0);

    # keep track of what we've loaded so someone doesn't put the same thing
    # into the import list in twice.
    my $loaded = {};

    my @actions = ();
    for my $option (@options) {
        next if exists($loaded->{$option});
        $loaded->{$option} = 1;

        if ($option eq ":initialize") {
            # note that the user promised to implement this. if the user
            # doesn't promise to implement this then we will have create our
            # own implementation to avoid errors.
            next;
        }

        if ($option eq ":handler") {
            {
                # this block makes our caller a child class of this class
                no strict 'refs';
                unshift(@{"${namespace}::ISA"}, __PACKAGE__);
            }

            # this is used by Web::Simple to not complain about keywords in
            # prototypes like HEAD and GET. but we need to extend it to classes
            # that implement us so we're adding it here.
            warnings::illegalproto->unimport();

            next;
        }

        # these keywords will be exported as proxies to the real methods
        if ($option =~ /^(config)$/x) {
            no strict 'refs';

            # need to predefine the exported method so that barewords work
            *{"${\__PACKAGE__}::${1}"} = *{"${namespace}::${1}"} = sub { return; };

            # this will establish the actual method in ->new()
            push(@TO_EXPORT, [ $namespace, $1 ]);

            next;
        }

        croak "${option} is not exported by the ${\__PACKAGE__} module";
    }

    # if we did not load ":initialize" (because the user did not ask to import
    # it) then we will replace the initialize method with an empty one so that
    # ->new gets to call *something* and doesn't just blow up.
    unless (exists($loaded->{':initialize'})) {
        no strict 'refs';
        no warnings 'redefine';
        *{"${\__PACKAGE__}::initialize"} = sub { return; };
    }

    return;
}

sub to_psgi_app {
    my $self = shift;

    # get the PSGI app from Web::Simple and wrap middleware around it
    my $app = $self->SUPER::to_psgi_app();

    # enable static document loading
    $app = $self->{'_core'}->enable_static($app);

    # enable sessions
    $app = $self->{'_core'}->enable_sessions($app);

    return $app;
}

# NOTE: your program can definitely implement ->dispatch_request instead of
# ->handler but ->handler will give you easier access to request and response
# data using Prancer::Request and Prancer::Response.
sub dispatch_request {
    my ($self, $env) = @_;

    my $request = Prancer::Request->new($env);
    my $response = Prancer::Response->new($env);
    my $session = Prancer::Session->new($env);

    return $self->handler($env, $request, $response, $session);
}

1;

=head1 NAME

Prancer

=head1 SYNOPSIS

When using as part of a web application:

    #!/usr/bin/env perl

    use strict;
    use warnings;
    use Plack::Runner;

    # this just returns a PSGI application. $x can be wrapped with additional
    # middleware before sending it along to Plack::Runner.
    my $x = MyApp->new("/path/to/foobar.yml")->to_psgi_app();

    # run the psgi app through Plack and send it everything from @ARGV. this
    # way Plack::Runner will get options like what listening port to use and
    # application server to use -- Starman, Twiggy, etc.
    my $runner = Plack::Runner->new();
    $runner->parse_options(@ARGV);
    $runner->run($x);

    package MyApp;

    use strict;
    use warnings;

    use Prancer qw(config :initialize :handler);

    sub initialize {
        my $self = shift;

        # in here we can initialize things like plugins

        return;
    }

    sub handler {
        my ($self, $env, $request, $response, $session) = @_;

        sub (GET + /) {
            $response->header("Content-Type" => "text/plain");
            $response->body("Hello, world!");
            return $response->finalize(200);
        }
    }

    1;

If you save the above snippet as C<myapp.psgi> and run it like this:

    plackup myapp.psgi

You will get "Hello, world!" in your browser. Or you can use Prancer as part of
a standalone command line application:

    #!/usr/bin/env perl

    use strict;
    use warnings;

    use Prancer qw(config);

    # the advantage to using Prancer in a standalone application is the ability
    # to use a standard configuration and to load plugins for things like
    # loggers and database connectors and template engines.
    my $x = Prancer->new("/path/to/foobar.yml");
    print "Hello, world!;

=head1 DESCRIPTION

TODO

=head1 CONFIGURATION

TODO

=head1 EXPORTABLE

This module exports one method.

=over

=item config

This method gives you access to L<Prancer::Config>.

=back

There are other keywords you can put into the import list that will have other
effects.

=over

=item :initialize

TODO

=item :handler

TODO

=back

=head1 CREDITS

This module could have been written except on the shoulders of the following
giants:

=over

=item

The name "Prancer" is a riff on the popular PSGI framework L<Dancer> and
L<Dancer2>. L<Prancer::Config> is derived directly from
L<Dancer2::Core::Role::Config>. Thank you to the
L<Dancer2|https://github.com/PerlDancer/Dancer2> team.

=item

L<Prancer::Database> is derived from L<Dancer::Plugin::Database>. Thank you to
David Precious.

=item

L<Prancer::Request>, L<Prancer::Request::Upload>, L<Prancer::Response>,
L<Prancer::Session> and the session modules are but thin wrappers with minor
modifications to L<Plack::Request>, L<Plack::Request::Upload>,
L<Plack::Response>, and L<Plack::Middleware::Session>. Thank you to Tatsuhiko
Miyagawa.

=item

The entire routing functionality of this module is offloaded to L<Web::Simple>.
Thank you to Matt Trout for some great code that I am able to easily leverage.

=back

=head1 COPYRIGHT

Copyright 2014 Paul Lockaby. All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

=over

=item L<Plack>
=item L<Web::Simple>

=back

=cut
