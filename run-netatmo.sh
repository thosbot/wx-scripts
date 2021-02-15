#!/bin/bash

source /opt/perl5/perlbrew/etc/bashrc
perlbrew use perl-5.28.0@nwx
cd ~/scripts
rm .netatmo-auth
./nwx.pl >/srv/www/em7b5.net/wx.html
