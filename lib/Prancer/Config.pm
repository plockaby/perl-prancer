package Prancer::Config;

use strict;
use warnings FATAL => 'all';

use File::Spec;
use Config::Any;
use Hash::Merge::Simple;
use Try::Tiny;

sub load {
    my ($class, $location) = @_;
    my $self = bless({}, $class);

    my @files = $self->_build_file_list($location);
    return $self->_load_config_files(@files);
}

sub _build_file_list {
    my ($self, $location) = @_;

    # an undef location means no config files for the caller
    return [] unless defined($location);

    my $running_env = $ENV{ENVIRONMENT} || $ENV{PLACK_ENV} || 'development';
    my @exts = Config::Any->extensions();
    my @files = ();

    foreach my $ext (@exts) {
        foreach my $file (
            [ $location, "config.${ext}" ],
            [ $location, "${running_env}.${ext}" ]
        ) {
            my $path = _normalize_path(@{$file});
            next unless (-r $path);

            push(@files, $path);
        }
    }

    return @files;
}

sub _load_config_files {
    my ($self, @files) = @_;

    return Hash::Merge::Simple->merge(
        map { $self->_load_config_file($_) } @files
    );
}

sub _load_config_file {
    my ($self, $file) = @_;
    my $config = {};

    try {
        my @files = ($file);
        my $tmp = Config::Any->load_files({
            'files' => \@files,
            'use_ext' => 1,
        })->[0];
        ($file, $config) = %{$tmp} if defined($tmp);
    } catch {
        my $error = (defined($_) ? $_ : "unknown");
        die "unable to parse configuration file: ${file}: ${error}\n";
    };

    return $config;
}

sub _normalize_path {
    my $path = File::Spec->catfile(@_);

    # this is a revised version of what is described in
    # http://www.linuxjournal.com/content/normalizing-path-names-bash
    # by Mitch Frazier
    my $seqregex = qr{
        [^/]*       # anything without a slash
        /\.\.(/|\z) # that is accompanied by two dots as such
    }x;

    $path =~ s{/\./}{/}gx;
    $path =~ s{$seqregex}{}gx;
    $path =~ s{$seqregex}{}x;

    # see https://rt.cpan.org/Public/Bug/Display.html?id=80077
    $path =~ s{^//}{/}x;
    return $path;
}

1;

=head1 NAME

Prancer::Config

=head1 SYNOPSIS

This module should not be used directly to access the logger. Instead, one
should use L<Prancer>.

=cut
