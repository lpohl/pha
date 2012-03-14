#!/usr/bin/perl

use lib '/opt/pha/etc';
use lib '/opt/pha/lib';

use KlasterConf;
use Data::Dumper;

my $href = Storable::lock_retrieve($CONFIG{INSTALLDIR}.'/var/klst.dat');

print $href->{STATUS}."\n";

