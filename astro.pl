#!/usr/bin/env perl

use strict;
use warnings;

use v5.10;

use Getopt::Long;
Getopt::Long::Configure('bundling');
use Pod::Usage;

use YAML::XS qw/ LoadFile /;
use JSON::XS;
use LWP::Simple;
use Digest::HMAC_SHA1;
use URI::Escape;
use POSIX qw/ strftime /;

my $VERBOSE;
my ($PATH, $DATE, $PLACE);

my $PHASE_MAP = {
    waxingcrescent => 'wax. crescent',
    firstquarter   => 'first qt.',
    waxinggibbous  => 'wax. gibbous',

    waninggibbous  => 'wan. gibbous',
    lastquarter    => 'last qt.',
    waningcrescent => 'wan. crescent',
};

exit(main(@ARGV));

sub main {
    GetOptions(
        'config|c=s' => \$PATH,
        'date|d=s'   => \$DATE,
        'place|p=s'  => \$PLACE,

        'help|h'     => sub { pod2usage(-exitstatus => 0, -verbose => 1) },
        'man'        => sub { pod2usage(-exitstatus => 0, -verbose => 2) },
        'verbose|v'  => \$VERBOSE,
    ) || pod2usage(1);

    note("Running $0");

    fail('No config') unless $PATH;
    fail('No date') unless $DATE;
    fail('No place') unless $PLACE;

    my $config = LoadFile $PATH || fail("Couldn't open $PATH");

    my $url = 'https://api.xmltime.com';
    note("Connecting to $url");
    my $tok = $config->{token};
    my $key = $config->{key};

    my $serv = 'astronomy';
    my $ts = strftime("%FT%T", gmtime());
    my $hmac = Digest::HMAC_SHA1->new($key);
    $hmac->add("$tok$serv$ts");
    my $sig = $hmac->b64digest;

    my %arg = (
        version => 3,
        placeid => $PLACE,
        startdt => $DATE,
        out     => 'js',
        lang    => 'eng',
        object  => 'sun,moon',
        types   => 'current,setrise,daylength',
    );

    $arg{accesskey} = $tok;
    $arg{timestamp} = $ts;
    $arg{signature} = $sig;

    my $query = join(';', map { "$_=" . uri_escape($arg{$_}) } keys %arg);
    my $resp = get("$url/$serv?$query");

    my $dat = {
        sunrise   => '',
        sunset    => '',
        daylength => '',

        moonrise  => '',
        moonset   => '',
        moonphase => '',
    };

    my $astro = decode_json $resp;
    foreach my $obj (@{ $astro->{locations}[0]->{astronomy}->{objects} }) {
        if ($obj->{name} eq 'sun') {
            my $today = $obj->{days}[0];
            $dat->{daylength} = $today->{daylength};

            foreach my $evt (@{$today->{events}}) {
                $dat->{'sun' . $evt->{type}} = get_time($evt->{hour}, $evt->{min});
            }
        }
        elsif ($obj->{name} eq 'moon') {
            my $ph = $obj->{current}->{moonphase};
            $dat->{moonphase} = $PHASE_MAP->{$ph} || $obj->{current}->{moonphase};

            my $today = $obj->{days}[0];
            foreach my $evt (@{$today->{events}}) {
                $dat->{'moon' . $evt->{type}} = get_time($evt->{hour}, $evt->{min});
            }
        }
    }
    say encode_json $dat;
}

sub get_time {
    if (length $_[0] == 1) {
        $_[0] = '0' . $_[0];
    }
    if (length $_[1] == 1) {
        $_[1] = '0' . $_[1];
    }
    return $_[0] . ':' . $_[1];
}

sub fail {
    # Turn on verbosity on error
    $VERBOSE = 1;
    note($_[0]);
    exit 1;
}

sub note {
    return unless $VERBOSE; # Only write output if verbose flag has been set

    my ($msg) = @_;

    # Create timestamp with microseconds
    my ($seconds, $microseconds) = gettimeofday();
    my $ts = strftime "%Y-%m-%d %H:%M:%S", localtime $seconds;
    $ts .= '.' . sprintf "%s", substr $microseconds, 0, 2;

    print STDERR "[$ts] $msg\n";
}

__END__

=head1 NAME

astro.pl - Download sun and moon stats from timeanddate.com.

=head1 SYNOPSIS

astro.pl

=head1 DESCRIPTION

astro.pl fetches sun and moon data for the date and place provided.

=head1 OPTIONS
 -c, --config   Config YAML with token and key
 -p, --place
 -d, --date     YYYY-MM-DD

 -h, --help     Display help message
     --man      Complete documentation
 -v, --verbose  Increase verbosity

=head1 AUTHOR

thosbot

=cut

