#!/usr/bin/perl

use lib qq(/opt/pha/lib);

use pha;
use Data::Dumper;

my $href = Storable::lock_retrieve($ARGV[0]);

print Dumper($href);

