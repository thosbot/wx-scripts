#!/usr/bin/env perl

use strict;
use warnings;

use v5.28;

use Getopt::Long;
Getopt::Long::Configure('bundling');
use Pod::Usage;

use YAML::XS qw/ LoadFile /;
use JSON::XS;
use LWP::UserAgent;
use Text::Caml;

use Data::Dumper;
use POSIX qw/ strftime /;
use Time::HiRes qw/ gettimeofday /;

my $VERBOSE;

exit(main(@ARGV));

sub main {
    GetOptions(
        'help|h'    => sub { pod2usage(-exitstatus => 0, -verbose => 1) },
        'man'       => sub { pod2usage(-exitstatus => 0, -verbose => 2) },
        'verbose|v' => \$VERBOSE,
    ) || pod2usage(1);

    note("Running $0");

    my $ua = LWP::UserAgent->new;
    $ua->default_header(
        'Content-Type' => 'application/x-www-form-urlencoded; charset=utf-8'
    );

    my $token = authenticate($ua);
    my $content = get_station_data($ua, $token);
    my $vars = extract_vars($content);
    write_html($vars);

    note("Done $0");
    exit 0;
}

# https://dev.netatmo.com/resources/technical/samplessdks/tutorials
sub authenticate {
    my ($ua) = @_;

    note("Authenticating");
    # Look for a stored authorization token
    my $token;
    if ( -e '.netatmo-auth' ) {
        note("Reading stored auth token");
        open( my $fh, '<:encoding(UTF-8)', '.netatmo-auth' )
            or fail("Error reading auth token: $!");
        my $auth = decode_json <$fh>;
        close $fh;
        $token = $auth->{access_token};
    }

    # Generate a new auth token
    if ( !$token ) {
        note("Requesting new auth token");
        my $config = LoadFile 'nwx.yml';
        my $res = $ua->post(
            'https://api.netatmo.com/oauth2/token',
            [
                client_id     => $config->{client_id},
                client_secret => $config->{client_secret},
                grant_type    => 'password',
                username      => $config->{username},
                password      => $config->{password},
                scope         => 'read_station',
            ]
        );

        if ( !$res->is_success ) {
            my $err = sprintf(
                "Auth request failed: %s %s", $res->code, $res->message
            );
            fail($err);
        }

        my $auth = decode_json $res->decoded_content;
        $token = $auth->{access_token};

        # Write auth response to dotfile
        open my $fh, '>', '.netatmo-auth';
        print $fh encode_json $auth;
        close $fh;
    }

    return $token;
}

# https://dev.netatmo.com/resources/technical/reference/weather/getstationsdata
sub get_station_data {
    my ($ua, $token) = @_;

    note("Getting station data");
    my $res = $ua->post(
        'https://api.netatmo.com/api/getstationsdata',
        [
            access_token => $token,
            # TODO: Get device ID from config.
            device_id    => '70:ee:50:1f:3c:48',
        ]
    );

    if ( !$res->is_success ) {
        if ( $res->code == 403 ) {
            # TODO
            # https://dev.netatmo.com/en-US/resources/technical/guides/authentication/refreshingatoken
            fail("Received 403 -- need to send refresh token request");
        }

        my $err = sprintf(
            "Auth request failed: %s %s", $res->code, $res->message
        );
        fail($err);
    }

    my $content = decode_json $res->decoded_content;
    return $content;
}

sub extract_vars {
    my ($content) = @_;

    my $body  = $content->{body};
    my $dev   = $body->{devices}->[0];
    my $mod   = $dev->{modules}->[0];

    my $epoch = $dev->{dashboard_data}->{time_utc};
    my $ts    = strftime "%a %d %b %Y %T %Z(%z)", localtime($epoch);

    # Get temperature from outdoor module
    my $temp_c = $mod->{dashboard_data}->{Temperature};
    my $temp_f = sprintf "%.1f", ($temp_c * 9) / 5 + 32;

    # Pressure only avails in indoor base station
    my $pressure_mb = $dev->{dashboard_data}->{Pressure};
    my $pressure_in = sprintf "%.1f", $pressure_mb * 0.02953;
    my $pressure_trend = $dev->{dashboard_data}->{pressure_trend};

    return {
        timestamp      => $ts,
        temp_f         => $temp_f,
        temp_c         => $temp_c,
        pressure_in    => $pressure_in,
        pressure_mb    => $pressure_mb,
        pressure_trend => $pressure_trend,
    }
}

sub write_html {
    my ($vars) = @_;

    # TODO: Take output file as command line arg.
    my $fname = "wx.html";
    note("Writing HTML output to $fname");

    my $tmpl = <<HTML;
<!-- {{timestamp}} -->
Currently {{temp_f}}&deg;F / {{temp_c}}&deg;C
HTML

    my $eng  = Text::Caml->new;
    my $view = $eng->render($tmpl, $vars);
    print STDOUT $view;
}

sub fail {
    # Turn on verbosity on error
    $VERBOSE = 1;
    note($_[0]);
    exit 1;
}

sub note {
    # Only write output if verbose flag has been set
    return unless $VERBOSE;

    my ($msg) = @_;

    # Create timestamp with microseconds
    my ($seconds, $microseconds) = gettimeofday();
    my $ts = strftime "%Y-%m-%d %H:%M:%S", localtime $seconds;
    $ts .= '.' . sprintf "%s", substr $microseconds, 0, 2;

    print STDERR "[$ts] $msg\n";
}

__END__

=head1 NAME

nwx.pl - Download latest Netatmo weather station data and write to HTML snippet.

=head1 SYNOPSIS

nwx.pl

=head1 DESCRIPTION

Blah, blah, blah ...

=head1 OPTIONS

 -h, --help     Display help message
     --man      Complete documentation
 -v, --verbose  Increase verbosity

=head1 AUTHOR

thosbot

=cut

