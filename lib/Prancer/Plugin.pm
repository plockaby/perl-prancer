package Prancer::Plugin;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = '1.00';

use Prancer::Core;

sub config {
    return Prancer::Core->new->config();
}

1;

=head1 NAME

Prancer::Plugin

=head1 SYNOPSIS

TODO

=cut
