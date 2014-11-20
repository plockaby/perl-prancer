package Prancer::Session::Store::Storable;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = "1.00";

use Plack::Session::Store::File;
use parent qw(Plack::Session::Store::File);

use Cwd ();
use Try::Tiny;
use Carp;

# even though this *should* work automatically, it was not
our @CARP_NOT = qw(Prancer Try::Tiny);

sub new {
    my ($class, $config) = @_;

    return try {
        my $path = Cwd::realpath(delete($config->{'path'}) || '/tmp');
        die "${path} does not exist\n" unless (-e $path);
        die "${path} is not readable\n" unless (-r $path);

        # i want names like "path"
        # but the Prancer::Middleware::Session really wants "dir"
        # so rename it
        $config->{'dir'} = $path;

        # set the storage type to Storable
        return bless($class->SUPER::new(%{$config || {}}), $class);
    } catch {
        my $error = (defined($_) ? $_ : "unknown");
        croak "could not initialize session handler: ${error}";
    };
}

1;

=head1 NAME

Prancer::Session::Store::Storable

=head1 SYNOPSIS

This module implements a session handler based on L<Stroable> files. Sessions
are stored at the configured path. This backend an perfectly be used in
production environments, but two things should be kept in mind: The content of
the session files is in plain text, and the session files should be purged by a
cron job.

To use this session handler, add this to your configuration file:

    session:
        store:
            driver: Prancer::Session::Store::Storable
            options:
                path: /tmp/prancer/sessions

=head1 OPTIONS

=over 4

=item path

B<REQUIRED> This indicates where sessions will be stored. If this path does not
exist then it will be created, if possible. This must be an absolute path and
it must be writable by the same user that is running the application server. If
this is not set then your application will not start. If this is set to a path
that your application cannot write to your application will not start. If this
is set to a path that doesn't exist and the path can't be created then your
application will not start.

=back

=cut
