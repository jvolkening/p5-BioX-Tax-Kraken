#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use BioX::Tax::Kraken;

my $tax = BioX::Tax::Kraken->new($ARGV[0]);

my $is = 0;
my @entries;
my %seen;
while (my $tid = <STDIN>) {
    chomp $tid;
    my $parent = $tax->parent($tid)
        // die "Missing parent for $tid\n";
    while (1) {
        my $name = $tax->name($tid)
            // die "Missing name for $tid\n";
        my $rank = $tax->rank($tid)
            // die "Missing rank for $tid\n";
        if (! $seen{$tid}) {
            push @entries, [$tid, $parent, $name, $rank];
            $seen{$tid} = 1;
        }
        last if ($tid == 1);
        $tid = $parent;
        $parent = $tax->parent($tid)
            // die "Missing parent for $tid\n";
    }
}
for my $e (sort {$a->[0] <=> $b->[0]} @entries) {
    say join "\t", @$e;
}
