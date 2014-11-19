package Prancer;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = "1.00";

# using Web::Simple in this context will implicitly make Prancer a subclass of
# Web::Simple::Application. that will cause a number of things to be imported
# into the Prancer namespace. see ->import below for more details.
use Web::Simple 'Prancer';

use Try::Tiny;
use Carp;

use Prancer::Core;
use Prancer::Request;
use Prancer::Response;

# even though this *should* work automatically, it was not
our @CARP_NOT = qw(Prancer Try::Tiny);

# the list of internal methods that will be created on the fly and exported
# to the caller. this makes things like the bareword call to "config" work.
our @TO_EXPORT = ();

# the list of internal methods that will be created on the fly and only
# implemented in ourselves. this makes things like "$app->config()" work.
our @EXPORT_OK = qw(config);

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
    # effectively makes "namespace::method" resolve to "$self->{'_core'}->method()"
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

    # these are things that will always
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

        if ($option eq ':initialize') {
            # note that we implemented it
            next;
        }

        if ($option eq ':handler') {
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

    # get the PSGI app from Web::Simple;
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
    my $session = undef;

    return $self->handler($env, $request, $response, $session);
}

1;

=head1 NAME

Prancer

=head1 SYNOPSIS

TODO

=cut
