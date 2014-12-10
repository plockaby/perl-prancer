package Prancer::Session::Store::Memory;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = '1.00';

use Plack::Session::Store;
use parent qw(Plack::Session::Store);

1;

=head1 NAME

Prancer::Session::Store::Memory

=head1 SYNOPSIS

This module implements a session handler where all sessions are kept in memory.
This B<SHOULD NOT BE USED IN PRODUCTION>. If the server restarts all of your
users will be logged out. If you are using a multi-process server like
L<Starman> then your users will be logged out whenever they connect to a
different process so basically every time they connect. This should be used
strictly for testing.

Though this will be the default session handler if none is configured, it can
be explicitly configured like this:

    session:
        store:
            driver: Prancer::Session::Store::Memory

=cut

