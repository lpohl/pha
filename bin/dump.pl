#!/usr/bin/perl

use Storable;
use Data::Dumper;

my $href = Storable::lock_retrieve($ARGV[0]);

print Dumper($href);

