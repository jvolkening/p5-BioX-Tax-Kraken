#!/usr/bin/perl

use strict;
use warnings;

use Test2::V0;

use FindBin;
use IPC::Cmd qw/can_run/;

use BioX::Tax::Kraken;

my $has_xz = can_run('xz');
chdir $FindBin::Bin;

my $test_db_xz      = 'test_data/taxDB.sub.xz';
my $test_db         = 'test_data/taxDB.sub';

my $tax = BioX::Tax::Kraken->new($test_db);

isa_ok (
    $tax,
    ['BioX::Tax::Kraken'],
    "returned BioX::Tax::Kraken object"
);

SKIP: {
    skip("Skipping xz tests, xz not available")
        if (! $has_xz);
    my $tax = BioX::Tax::Kraken->new($test_db_xz);

    isa_ok (
        $tax,
        ['BioX::Tax::Kraken'],
        "returned BioX::Tax::Kraken object"
    );
}

done_testing;
exit;
