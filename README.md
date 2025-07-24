# Wx Scripts

A collection of weather-related Perl scripts for fetching astronomical data, weather station data, and weather forecast discussions.

## Overview

- **`astro.pl`** - Fetches sun and moon astronomical data from timeanddate.com API
- **`netatmo.pl`** - Downloads weather station data from Netatmo API and generates HTML output
- **`discussion.pl`** - Downloads NWS area forecast discussion and converts to speech using Google TTS
- **`wx.sh`** - Simple bash script to fetch weather data from OpenWeatherMap API

## Dependencies

### System Dependencies (Debian/Ubuntu)

```bash
apt install libssl-dev zlib1g-dev libxml2-dev
```

### Perl Dependencies (CPAN)

```bash
cpanm YAML::XS JSON::XS Net::SSLeay IO::Socket::SSL LWP::UserAgent LWP::Protocol::https URI Text::Caml File::XDG XML::LibXML MIME::Base64 Digest::HMAC_SHA1
```

## Scripts

### astro.pl

Downloads sun and moon astronomical data for a specific date and location using the timeanddate.com API. Outputs JSON with sunrise, sunset, moonrise, moonset, day length, and moon phase information.

Run `./astro.pl --man` for detailed usage information.

### netatmo.pl

Fetches weather data from a Netatmo personal weather station and generates an HTML snippet. Uses OAuth2 authentication with automatic token refresh.

Run `./netatmo.pl --man` for detailed usage information.

### discussion.pl

Downloads the latest NWS (National Weather Service) area forecast discussion and converts sections to speech using Google Text-to-Speech API. Outputs audio files in Opus format.

Run `./discussion.pl --man` for detailed usage information.

### wx.sh

Simple bash script that fetches weather data from the OpenWeatherMap API for Philadelphia coordinates.

## Helper Scripts

- **`run-astro.sh`** - Wrapper script to run astro.pl with current date for Philadelphia
- **`run-netatmo.sh`** - Wrapper script to run netatmo.pl (legacy reference to nwx.pl)

## Setup Instructions

1. Install system dependencies
2. Install Perl dependencies via CPAN
3. Create configuration files for the scripts you want to use
4. Set up API credentials as needed
5. Run `./script.pl --man` for detailed usage instructions for each script

## Author

thosbot
