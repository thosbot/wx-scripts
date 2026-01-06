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
use LWP::Protocol::https;
use Text::Caml;
use File::XDG;

use POSIX qw/ strftime /;
use Time::HiRes qw/ gettimeofday /;
use File::Spec::Functions qw/ catfile /;

my $xdg = File::XDG->new(name => 'wx-scripts');
sub get_auth_file_path {
    return $xdg->config_home . '/netatmo-auth.json';
}

exit(main(@ARGV));

sub main {
    my $config_file;
    my $output_file;

    GetOptions(
        'config|c=s' => \$config_file,
        'output|o=s' => \$output_file,
        'help|h'     => sub { pod2usage(-exitval => 0, -verbose => 1) },
        'man'        => sub { pod2usage(-exitval => 0, -verbose => 2) },
    ) || pod2usage(1);

    pod2usage(
        { -msg => "Missing required --config option", -exitval => 1, -verbose => 1 }
    ) unless $config_file;

    my $config;
    eval {
        $config = LoadFile $config_file;
    };
    if ($@ or !$config) {
        die "Failed to load or parse config file '$config_file': $@";
    }

    my $device_id = $config->{device_id}
        or die "Failed to find device_id in config file '$config_file'";

    my $ua = LWP::UserAgent->new;
    $ua->default_header(
        'Content-Type' => 'application/x-www-form-urlencoded; charset=utf-8'
    );

    my $token = authenticate($ua, $config);
    my $data  = get_station_data($ua, $token, $device_id);
    my $vars  = extract_vars($data);

    write_html($vars, $output_file);
}

sub authenticate {
    my ($ua, $config) = @_;

    say "Authenticating ...";
    my $auth = read_auth_file();
    if (!$auth) {
        return authenticate_oauth($ua, $config);
    }

    # Always refresh token :/
    my $token = $auth->{access_token};
    eval {
        $token = refresh_token($ua, $config, $auth);
    };
    if ($@) {
        say "Refresh failed, re-authenticating ...";
        $token = authenticate_oauth($ua, $config);
    }
    return $token;
}

sub authenticate_oauth {
    my ($ua, $config) = @_;

    my $client_id     = $config->{client_id};
    my $client_secret = $config->{client_secret};
    my $redirect_uri  = $config->{redirect_uri} // 'http://localhost';

    my $auth_url = "https://api.netatmo.com/oauth2/authorize?" .
        "client_id=$client_id" .
        "&redirect_uri=$redirect_uri" .
        "&scope=read_station" .
        "&response_type=code" .
        "&state=xyz";

    say "Please open the following URL in your browser and authorize the app:";
    say $auth_url;
    print "Enter the code parameter from the redirected URL: ";
    chomp(my $code = <STDIN>);

    my $res = $ua->post(
        'https://api.netatmo.com/oauth2/token',
        [
            grant_type    => 'authorization_code',
            client_id     => $client_id,
            client_secret => $client_secret,
            code          => $code,
            redirect_uri  => $redirect_uri,
        ]
    );

    if (!$res->is_success) {
        die "Failed to get OAuth token: " . $res->status_line . "\n" . $res->decoded_content;
    }

    my $auth;
    eval {
        $auth = decode_json($res->decoded_content);
    };
    if ($@ or !$auth) {
        die "Failed to parse auth response: $@";
    }
    write_auth_file($auth);

    return $auth->{access_token};
}

sub refresh_token {
    my ($ua, $config, $auth) = @_;

    if (!$auth) {
        $auth = read_auth_file();
    }

    my $refresh_token = $auth->{refresh_token};
    if (!$refresh_token) {
        die "Failed to find refresh_token in auth file";
    }

    my $client_id     = $config->{client_id};
    my $client_secret = $config->{client_secret};

    say "Refreshing access token ...";
    my $res = $ua->post(
        'https://api.netatmo.com/oauth2/token',
        [
            grant_type    => 'refresh_token',
            refresh_token => $refresh_token,
            client_id     => $client_id,
            client_secret => $client_secret,
        ]
    );

    if (!$res->is_success) {
        die "Failed to refresh token: " . $res->status_line . "\n" . $res->decoded_content;
    }

    my $new_auth;
    eval {
        $new_auth = decode_json($res->decoded_content);
    };
    if ($@ or !$new_auth) {
        die "Failed to parse refresh response: $@";
    }
    write_auth_file($new_auth);

    return $new_auth->{access_token};
}

sub read_auth_file {
    my $auth;
    my $auth_file = get_auth_file_path();
    eval {
        open my $fh, '<:encoding(UTF-8)', $auth_file
            or die "Failed to read auth token file: $!";
        $auth = decode_json(<$fh>);
        close $fh;
    };
    # XXX: Does $@ only represent the file close?
    if ($@ or !$auth) {
        die "Failed to load or parse auth file '$auth_file': $@";
    }
    return $auth;
}

sub write_auth_file {
    my ($auth_data) = @_;

    # Ensure the config directory exists
    my $config_dir = $xdg->config_home;
    if (!-d $config_dir) {
        mkdir $config_dir, 0700
            or die "Failed to create config directory '$config_dir': $!";
    }

    my $auth_file = get_auth_file_path();
    open my $fh, '>', $auth_file
        or die "Failed to open auth file for writing: $!";
    chmod 0600, $auth_file;
    # TODO: Error check encode_json.
    print $fh encode_json($auth_data);
    close $fh;
}

# https://dev.netatmo.com/resources/technical/reference/weather/getstationsdata
sub get_station_data {
    my ($ua, $token, $device_id) = @_;

    say "Getting station data ...";
    my $res = $ua->post(
        'https://api.netatmo.com/api/getstationsdata',
        [
            access_token => $token,
            device_id    => $device_id,
        ]
    );

    if ( !$res->is_success ) {
        if ( $res->code == 403 ) {
            die "Failed to access API (403 Forbidden): token may be expired";
        }

        die "Failed to get station data: " . $res->code . " " . $res->message;
    }

    my $data;
    eval {
        $data = decode_json($res->decoded_content);
    };
    if ($@ or !$data) {
        die "Failed to parse API response: $@";
    }

    return $data;
}

sub extract_vars {
    my ($data) = @_;

    my $body  = $data->{body};
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
    my ($vars, $output_file) = @_;

    my $tmpl = <<HTML;
<!-- {{timestamp}} -->
Currently {{temp_f}}&deg;F / {{temp_c}}&deg;C
HTML

    my $eng  = Text::Caml->new;
    my $view = $eng->render($tmpl, $vars);

    if ($output_file) {
        say "Writing HTML output to $output_file ...";
        open my $fh, '>', $output_file
            or die "Failed to open output file '$output_file': $!";
        print $fh $view;
        close $fh;
    } else {
        print STDOUT $view;
    }
}

__END__

=head1 NAME

netatmo.pl - Download latest Netatmo weather station data and write to HTML
snippet.

=head1 SYNOPSIS

netatmo.pl [options]

=head1 DESCRIPTION

Fetches weather data from a Netatmo weather station and writes an HTML snippet.

This script uses OAuth2 authentication to access the Netatmo API. On first run,
you will be prompted to visit a URL in your browser to authorize the
application and paste back the resulting code. After initial authorization,
the script will automatically refresh the access token as needed.

=head1 CONFIGURATION

You must provide a YAML config file with the following keys:

  client_id:      Your Netatmo API client ID
  client_secret:  Your Netatmo API client secret
  redirect_uri:   The redirect URI registered with your Netatmo app
  device_id:      The MAC address of your Netatmo base station

Example nwx.yml:

  client_id:      "your_client_id"
  client_secret:  "your_client_secret"
  redirect_uri:   "http://localhost"
  device_id:      "ff:ff:ff:ff:ff:ff"

=head1 OPTIONS

 -c, --config FILE  Path to config YAML file (required)
 -o, --output FILE  Output HTML file (default: STDOUT)
 -h, --help         Display help message
     --man          Complete documentation
 -v, --verbose      Verbose output

=head1 OAUTH FLOW

On first run, the script will print a URL. Open this URL in your browser, log
in to Netatmo, and authorize the application. You will be redirected to your
redirect_uri with a C<code> parameter in the URL. Paste this code back into
the script prompt to complete authentication.

The script will store the access and refresh tokens in a local file (default:
.netatmo-auth) for future use.

=head1 AUTHOR

thosbot

=cut

