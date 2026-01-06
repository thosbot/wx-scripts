#!/usr/bin/env perl

use strict;
use warnings;

use v5.10;

use Getopt::Long;
Getopt::Long::Configure('bundling');
use Pod::Usage;

use YAML::XS qw/ LoadFile /;
use JSON::XS;
use LWP::UserAgent;
use Text::Caml;

use POSIX qw/ strftime /;
use Time::HiRes qw/ gettimeofday /;


exit(main(@ARGV));

sub main {
    GetOptions(
        'help|h'    => sub { pod2usage(-exitstatus => 0, -verbose => 1) },
        'man'       => sub { pod2usage(-exitstatus => 0, -verbose => 2) },
        'verbose|v' => \$VERBOSE,
    ) || pod2usage(1);


    my $ua = LWP::UserAgent->new;
    $ua->default_header(
        'Content-Type' => 'application/x-www-form-urlencoded; charset=utf-8'
    );

    my $token = authenticate($ua);
    my $content = get_station_data($ua, $token);
    my $vars = extract_vars($content);
    write_html($vars);
}

# https://dev.netatmo.com/resources/technical/samplessdks/tutorials
sub authenticate {
    my ($ua) = @_;

    # Look for a stored authorization token
    say "Authenticating ...";
    my $token;
    if ( -e '.netatmo-auth' ) {
        say "Reading stored auth token";
        open( my $fh, '<:encoding(UTF-8)', '.netatmo-auth' )
            or die "Error reading auth token: $!";
        my $auth = decode_json(<$fh>);
        close $fh;
        $token = $auth->{access_token};
    }

    # Generate a new auth token
    if ( !$token ) {
        my $config = LoadFile 'nwx.yml';
        say "Requesting new auth token";
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
            die $err;
        }

        my $auth = decode_json($res->decoded_content);
        $token = $auth->{access_token};

        # Write auth response to dotfile
        open my $fh, '>', '.netatmo-auth';
        print $fh encode_json($auth);
        close $fh;
    }

    return $token;
}

# https://dev.netatmo.com/resources/technical/reference/weather/getstationsdata
sub get_station_data {
    my ($ua, $token) = @_;

    say "Getting station data";
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
            die "Received 403 -- need to send refresh token request";
        }

        my $err = sprintf(
            "Auth request failed: %s %s", $res->code, $res->message
        );
        die $err;
    }

    return decode_json($res->decoded_content);
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
    say "Writing HTML output to $fname";

    my $tmpl = <<HTML;
<!-- {{timestamp}} -->
Currently {{temp_f}}&deg;F / {{temp_c}}&deg;C
HTML

    my $eng  = Text::Caml->new;
    my $view = $eng->render($tmpl, $vars);
    print STDOUT $view;
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

=head1 AUTHOR

thosbot

=cut

