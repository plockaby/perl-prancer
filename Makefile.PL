#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'          => 'prancer',
    'AUTHOR'        => 'Paul Lockaby <plockaby AT cpan DOT org>',
    'VERSION_FROM'  => 'lib/Prancer.pm',
    'PREREQ_PM'     => {
        'Plack'                      => '0.9968',  # same version required by Web::Simple
        'Plack::Middleware::Session' => '0.23',
        'Web::Simple'                => '0.30',
        'Try::Tiny'                  => '0',
        'Config::Any'                => '0',
        'Hash::MultiValue'           => '0',
        'URI'                        => '0',
        'warnings::illegalproto'     => '0',
    },
    'INSTALLDIRS'   => (($] < 5.011) ? 'perl' : 'site'),

    ((ExtUtils::MakeMaker->VERSION() lt '6.25') ?
        ('PL_FILES' => { })            : ()),
    ((ExtUtils::MakeMaker->VERSION() gt '6.30') ?
        ('LICENSE'  => 'perl')         : ()),
);
