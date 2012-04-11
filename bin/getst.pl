#!/usr/bin/perl

use Storable;
use Data::Dumper;

my $file = '/opt/pha/var/status.dat';

if (-f $file) {
	my $href = Storable::lock_retrieve($file);
	print $href->{STATUS}."\n";
} else {
	print "OFFLINE\n";
}
