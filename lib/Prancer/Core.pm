package Prancer::Core;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = '0.990004';

use Cwd ();
use Module::Load ();
use Try::Tiny;
use Carp;

use Prancer::Config;

# even though this *should* work automatically, it was not
our @CARP_NOT = qw(Prancer Try::Tiny);

sub new {
    my ($class, $configuration_file) = @_;

    # already got an object
    return $class if ref($class);

    # this is a singleton
    my $instance = undef;
    {
        no strict 'refs';
        $instance = \${"${class}::_instance"};
        return $$instance if defined($$instance);
    }

    # ok so the singleton doesn't exist so create an instance
    my $self = bless({}, $class);

    # load configuration options if we were given a config file
    if (defined($configuration_file)) {
        $self->{'_config'} = Prancer::Config->load($configuration_file);
    }

    $$instance = $self;
    return $self;
}

sub config {
    my $self = shift;
    return $self->{'_config'};
}

sub enable_static {
    my ($self, $app) = @_;
    return $app unless defined($self->{'_config'});

    my $config = $self->{'_config'}->remove('static');
    return $app unless defined($config);

    try {
        # this intercepts requests for documents under the configured URL
        # and checks to see if the requested file exists in the configured
        # file system path. if it does exist then it is served up. if it
        # doesn't exist then the request will pass through to the handler.
        die "no url is configured for the static file loader\n" unless defined($config->{'url'});
        my $url = $config->{'url'};
        die "no path is configured for the static file loader\n" unless defined($config->{'path'});
        my $path = Cwd::realpath($config->{'path'});
        die "${\$config->{'path'}} does not exist\n" unless defined($path);
        die "${\$config->{'path'}} is not readable\n" unless (-r $path);

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

    return $app;
}

sub enable_sessions {
    my ($self, $app) = @_;
    return $app unless defined($self->{'_config'});

    my $config = $self->{'_config'}->remove("session");
    return $app unless defined($config);

    try {
        # load the session state module first
        # this will probably be a cookie
        my $state_module = undef;
        my $state_options = undef;
        if (ref($config->{'state'}) && ref($config->{'state'}) eq "HASH") {
            $state_module = $config->{'state'}->{'driver'};
            $state_options = $config->{'state'}->{'options'};
        }

        # make sure state options are legit
        if (defined($state_options) && (!ref($state_options) || ref($state_options) ne "HASH")) {
            die "session state configuration options are invalid -- expected a HASH\n";
        }

        # set defaults and then load the state module
        $state_options ||= {};
        $state_module ||= "Prancer::Session::State::Cookie";
        Module::Load::load($state_module);

        # set the default for the session name because the plack
        # default is stupid
        $state_options->{'session_key'} ||= "PSESSION";

        # load the store module second
        my $store_module = undef;
        my $store_options = undef;
        if (ref($config->{'store'}) && ref($config->{'store'}) eq "HASH") {
            $store_module = $config->{'store'}->{'driver'};
            $store_options = $config->{'store'}->{'options'};
        }

        # make sure store options are legit
        if (defined($store_options) && (!ref($store_options) || ref($store_options) ne "HASH")) {
            die "session store configuration options are invalid -- expected a HASH\n";
        }

        # set defaults and then load the store module
        $store_options ||= {};
        $store_module ||= "Prancer::Session::Store::Memory";
        Module::Load::load($store_module);

        require Plack::Middleware::Session;
        $app = Plack::Middleware::Session->wrap($app,
            'state' => $state_module->new(%{$state_options}),
            'store' => $store_module->new(%{$store_options}),
        );
    } catch {
        my $error = (defined($_) ? $_ : "unknown");
        carp "initialization warning generated while trying to load the session handler: ${error}";
    };

    return $app;
}

1;
