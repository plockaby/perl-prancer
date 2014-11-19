#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Prancer qw(config);
# use Prancer;

sub main {
    # figure out where exist to make finding config files possible
    my (undef, $root, undef) = File::Basename::fileparse($0);

	# this just returns a prancer object so we can get access to configuration
	# options and other awesome things like plugins.
	my $app = Prancer->new("${root}/foobar.yml");

    print "hello, goodbye. foo = " . $app->config->get('foo') . " or " . config->get('foo') . "\n";

    return;
}

main(@ARGV) unless caller;

1;
