#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use File::Temp qw(:seekable);
use ExtUtils::H2PM;

my $dir = File::Temp->newdir();

foreach my $packfile
    (qw(test_default_export test_no_export test_use_export test_use_export_ok))
{
    
    module "TEST";
    include "t/test.h", local => 1;
    constant "DEFINED_CONSTANT";
    if ($packfile eq 'test_no_export') {
        no_export;
    } elsif ($packfile eq 'test_use_export') {
        use_export;
    } elsif ($packfile eq 'test_use_export_ok') {
        use_export_ok;
    }
    write_output "${dir}/TEST.pm";

    my $perl = $^X;
    my $ftemp = File::Temp->new(TEMPLATE=>"${packfile}_XXXX",
                                SUFFIX=> '.pl',
                                DIR=>$dir,
        );
    my $fn = $ftemp->filename;
    my $val;

    make_testfile($fn,'TEST::DEFINED_CONSTANT');
    $val = `$perl -I$dir $fn`;
    
    is($val,10,"$packfile; use TEST; TEST::DEFINED_CONSTANT");

    make_testfile($fn,'DEFINED_CONSTANT');
    $val = `$perl -I$dir $fn`;
    is($val, ($packfile eq 'test_use_export' ?10:'undef'),
       "$packfile;  use TEST; DEFINED_CONSTANT");

    make_testfile($fn,'DEFINED_CONSTANT','DEFINED_CONSTANT');
    $val = `$perl -I$dir $fn`;    
    is($val, ($packfile ne 'test_no_export' ? 10 : 'undef'),
       "$packfile; use TEST qw(DEFINED_CONSTANT) ; DEFINED_CONSTANT");

}


sub make_testfile {
    my $filename = shift;
    my $var = shift;
    my $useopt = shift;

    open(F,">$filename") || die "error opening $filename for writing";
    print F "#!$^X\n";
    print F "use strict;\n";
    print F "use TEST ";
    if (defined($useopt) && $useopt ne '') {
        print F "qw($useopt)";
    }
    print F ";\n";
    print F "print eval('$var;') || 'undef';";
    close(F);
}



done_testing;
