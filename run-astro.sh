#!/bin/bash

source /opt/perl5/perlbrew/etc/bashrc
perlbrew use perl-5.32.0@wx-scripts
today=$(date '+%Y-%m-%d')
./astro.pl --date $today --place usa/philadelphia --config ~/.config/thosbot/astro.yaml >~/.cache/astro.json
