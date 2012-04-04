#!/usr/bin/perl

use lib '/opt/pha/etc';
use lib '/opt/pha/lib';

use pha;
use Data::Dumper;

my $href = Storable::lock_retrieve($CONFIG{INSTALLDIR}.'/var/status.dat');

print $href->{STATUS}."\n";

