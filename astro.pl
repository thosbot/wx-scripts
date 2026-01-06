#!/usr/bin/env perl

# See: https://dev.timeanddate.com/docs/astro

use strict;
use warnings;

use v5.10;

use Getopt::Long;
Getopt::Long::Configure('bundling');
use Pod::Usage;

use Data::Dumper;
use YAML::XS qw/ LoadFile /;
use JSON::XS;
use LWP::Simple;
use LWP::Protocol::https;
use Digest::HMAC_SHA1;
use URI::Escape;
use POSIX qw/ strftime /;

my ($PATH, $DATE, $PLACE);

my $PHASE_MAP = {
    waxingcrescent => 'wax. crescent',
    firstquarter   => 'first qt.',
    secondquarter  => 'second qt.',
    waxinggibbous  => 'wax. gibbous',
    fullmoon       => 'full moon',

    waninggibbous  => 'wan. gibbous',
    thirdquarter   => 'third qt.',
    lastquarter    => 'last qt.',
    waningcrescent => 'wan. crescent',
    newmoon        => 'new moon',
};

exit(main(@ARGV));

sub main {
    GetOptions(
        'config|c=s' => \$PATH,
        'date|d=s'   => \$DATE,
        'place|p=s'  => \$PLACE,

        'help|h'     => sub { pod2usage(-exitstatus => 0, -verbose => 1) },
        'man'        => sub { pod2usage(-exitstatus => 0, -verbose => 2) },
    ) || pod2usage(1);

    die('No config') unless $PATH;
    die('No date') unless $DATE;
    die('No place') unless $PLACE;

    my $config = LoadFile $PATH || die("Couldn't open $PATH");

    my $domain = 'https://api.xmltime.com';

    my $tok = $config->{token};
    my $key = $config->{key};

    my $api = 'astronomy';
    my $ts = strftime("%FT%T", gmtime());
    my $hmac = Digest::HMAC_SHA1->new($key);
    $hmac->add("$tok$api$ts");
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

    my $query = join('&', map { "$_=" . uri_escape($arg{$_}) } keys %arg);
    my $url = "$domain/$api?$query";
    my $resp = get($url);

    my $dat = {
        date      => '',
        sunrise   => '',
        sunset    => '',
        daylength => '',
        moonrise  => '',
        moonset   => '',
        moonphase => '',
    };

    my $astro = decode_json($resp);
    foreach my $obj (@{ $astro->{locations}[0]->{astronomy}->{objects} }) {
        if ($obj->{name} eq 'sun') {
            my $day = $obj->{days}[0];
            $dat->{date} = $day->{date};
            $dat->{daylength} = $day->{daylength};

            foreach my $evt (@{$day->{events}}) {
                $dat->{'sun' . $evt->{type}} = get_time($evt->{hour}, $evt->{min});
            }
        }
        elsif ($obj->{name} eq 'moon') {
            my $ph = $obj->{current}->{moonphase};
            $dat->{moonphase} = $PHASE_MAP->{$ph} || $obj->{current}->{moonphase};

            my $day = $obj->{days}[0];
            foreach my $evt (@{$day->{events}}) {
                $dat->{'moon' . $evt->{type}} = get_time($evt->{hour}, $evt->{min});
            }
        }
    }
    say encode_json($dat);
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

__END__

=head1 NAME

astro.pl - Download sun and moon stats from timeanddate.com.

=head1 SYNOPSIS

astro.pl --date [YYYY-MM-DD] --place [PLACE-ID] --config [CONFIG-PATH]

=head1 DESCRIPTION

astro.pl fetches sun and moon data for the date and place provided.

=head1 OPTIONS
 -c, --config   Config YAML with token and key
 -p, --place
 -d, --date     YYYY-MM-DD
 -h, --help     Display help message
     --man      Complete documentation

=head1 AUTHOR

thosbot

=cut

