#!/usr/bin/perl

use Test::Most;
use Test::Pod;
use Mojo::File qw(path);

my $file = path(__FILE__)->dirname->sibling('testapi.pm');

# Read the entire file and use a multiline regex to find empty headings
if ($file->slurp =~ /^=head[1-4]\s*$/m) {
    die "Empty POD heading (=headX with no text) found in $file\n";
}

all_pod_files_ok("$file");
