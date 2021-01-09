#!/usr/bin/env perl

use strict;
use warnings;

use v5.28;

use Getopt::Long;
Getopt::Long::Configure('bundling');
use Pod::Usage;

use JSON::XS;
use LWP::UserAgent;
use XML::LibXML;
use MIME::Base64;
use Data::Dumper;

use POSIX qw/ strftime /;
use Time::HiRes qw/ gettimeofday /;

my $VERBOSE;

exit(main(@ARGV));

sub main {
    # TODO: Take station ID as command line arg.
    GetOptions(
        'help|h'    => sub { pod2usage(-exitstatus => 0, -verbose => 1) },
        'man'       => sub { pod2usage(-exitstatus => 0, -verbose => 2) },
        'verbose|v' => \$VERBOSE,
    ) || pod2usage(1);

    note("Running $0");

    note('Getting area forecast discussion');
    my $req = HTTP::Request->new(
        'GET',
        'https://forecast.weather.gov/product.php?'
            . 'site=PHI&issuedby=PHI&product=AFD&format=TXT&version=1&glossary=0'
            . '&highlight=off',
        [ 'Content-Type' => 'application/x-www-form-urlencoded; charset=utf-8' ],
    );
    my $ua = LWP::UserAgent->new();
    my $res = $ua->request($req);

    if (!$res->is_success) {
        my $err = sprintf(
            "AFD request failed: %s %s", $res->code, $res->message
        );
        fail($err);
    }

    my $dom = XML::LibXML->load_html(
        string          => $res->decoded_content,
        recover         => 1,
        suppress_errors => 1,
    );
    my $xpath = '//pre[@id="proddiff"]';

    my $i = 1;
    my @parts = ('AFDPHI(.*)SHORT TERM', 'SHORT TERM(.*)LONG TERM', 'LONG TERM(.*)AVIATION');
    foreach my $p (@parts) {
        say $p;

        my $afd;
        if ($dom->findnodes($xpath)->to_literal_list->[0] =~ m/$p/gs) {
            $afd = $1;
        } else {
            fail('AFD regex failed')
        }
        # say $afd;

        my $param = {
          audioConfig => {
            audioEncoding => "OGG_OPUS",
            pitch => 0,
            speakingRate => 1,
          },
          input => {
            text => $afd,
          },
          voice => {
            languageCode => "en-US",
            name => "en-US-Wavenet-H", # C, E, F, H
          },
        };
        my $data = encode_json $param;

        my $key;
        $req = HTTP::Request->new(
            'POST',
            'https://texttospeech.googleapis.com/v1/text:synthesize?key=' . $key,
            [ 'Content-Type' => 'application/json; charset=utf-8' ],
            $data,
        );
        $res = $ua->request($req);

        if (!$res->is_success) {
            my $err = sprintf(
                "Speech request failed: %s %s\n%s",
                $res->code, $res->message, $res->decoded_content,
            );
            fail($err);
        }
        my $content = decode_json $res->content;

        my $filename = 'afd-' . $i . '.opus';
        open(my $fh, '>', $filename) or die "Can't open file";
        print $fh decode_base64 $content->{audioContent};
        close $fh;
        $i++;
    }

    note("Done $0");
    exit 0;
}

sub fail {
    # Turn on verbosity on error
    $VERBOSE = 1;
    note('ERRO ' . $_[0]);
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

discussion.pl - Get the latest NWS area forcast discussion and pass to speech proc.


=head1 SYNOPSIS

discussion.pl

=head1 DESCRIPTION

Blah, blah, blah ...

=head1 OPTIONS

 -h, --help     Display help message
     --man      Complete documentation
 -v, --verbose  Increase verbosity

=head1 AUTHOR

thosbot

=cut

