package Prancer::Config;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = "1.00";

use File::Spec;
use Config::Any;
use Storable qw(dclone);
use Try::Tiny;
use Carp;

# even though this *should* work automatically, it was not
our @CARP_NOT = qw(Prancer Try::Tiny);

sub load {
    my ($class, $path) = @_;
    my $self = bless({}, $class);

    # find config files, load them
    my $files = $self->_build_file_list($path);
    $self->{'_config'} = $self->_load_config_files($files);

    return $self;
}

sub has {
    my ($self, $key) = @_;
    return exists($self->{'_config'}->{$key});
}

sub get {
    my ($self, $key, $default) = @_;

    # only return things if the are running in a non-void context
    if (defined(wantarray())) {
        my $value = undef;

        if (exists($self->{'_config'}->{$key})) {
            $value = $self->{'_config'}->{$key};
        } else {
            $value = $default;
        }

        # nothing to return
        return unless defined($value);

        # make a clone to avoid changing things
        # through inadvertent references.
        $value = dclone($value) if ref($value);

        if (wantarray() && ref($value)) {
            # return a value rather than a reference
            if (ref($value) eq 'HASH') {
                return %{$value};
            }
            if (ref($value) eq 'ARRAY') {
                return @{$value};
            }
        }

        # return a reference
        return $value;
    }

    return;
}

sub set {
    my ($self, $key, $value) = @_;

    my $old = undef;
    $old = $self->get($key) if defined(wantarray());

    if (ref($value)) {
        # make a copy of the original value to avoid inadvertently changing
        # things through inadvertent references
        $self->{'_config'}->{$key} = dclone($value);
    } else {
        # can't clone non-references
        $self->{'_config'}->{$key} = $value;
    }

    if (wantarray() && ref($old)) {
        # return a value rather than a reference
        if (ref($old) eq 'HASH') {
            return %{$old};
        }
        if (ref($old) eq 'ARRAY') {
            return @{$old};
        }
    }

    return $old;
}

sub remove {
    my ($self, $key) = @_;

    my $old = undef;
    $old = $self->get($key) if defined(wantarray());

    delete($self->{'_config'}->{$key});

    if (wantarray() && ref($old)) {
        # return a value rather than a reference
        if (ref($old) eq 'HASH') {
            return %{$old};
        }
        if (ref($old) eq 'ARRAY') {
            return @{$old};
        }
    }

    return $old;
}

sub _build_file_list {
    my ($self, $path) = @_;

    # an undef location means no config files for the caller
    return [] unless defined($path);

    # if the path is a file or a link then there is only one config file
    return [ $path ] if (-e $path && (-f $path || -l $path));

    # since we already handled files/symlinks then if the path is not a
    # directory then there is very little we can do
    return [] unless (-d $path);

    # figure out what environment we are operating in by looking in several
    # well known (to the PSGI world) environment variables. if none of them
    # exist then we are probably in dev.
    my $env = $ENV{'ENVIRONMENT'} || $ENV{'PLACK_ENV'} || 'development';

    my @files = ();
    for my $ext (Config::Any->extensions()) {
        for my $file (
            [ $path, "config.${ext}" ],
            [ $path, "${env}.${ext}" ]
        ) {
            my $file_path = _normalize_file_path(@{$file});
            push(@files, $file_path) if (-r $file_path);
        }
    }

    return \@files;
}

sub _load_config_files {
    my ($self, $files) = @_;

    return merge(
        map { $self->_load_config_file($_) } @{$files}
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
        croak "unable to parse ${file}: ${error}";
    };

    return $config;
}

sub _normalize_file_path {
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

# stolen from Hash::Merge::Simple
sub merge {
    my ($left, @right) = @_;

    return $left unless @right;
    return merge($left, merge(@right)) if @right > 1;

    my ($right) = @right;
    my %merged = %{$left};

    for my $key (keys %{$right}) {
        my ($hr, $hl) = map { ref $_->{$key} eq 'HASH' } $right, $left;

        if ($hr and $hl) {
            $merged{$key} = merge($left->{$key}, $right->{$key});
        } else {
            $merged{$key} = $right->{$key};
        }
    }

    return \%merged;
}

1;
