#!/usr/bin/perl -w

use strict;
use Test::More tests => 6;
use Test::Output qw( stdout_from );

use ExtUtils::H2PM;

sub evalordie
{
   my $code = shift;
   my $ret = eval $code;
   $@ and die $@;
   $ret;
}

my $code;

$code = stdout_from {
         module "TEST";
         include "t/test.h", local => 1;
         constant "DEFINED_CONSTANT";
         write_perl;
      };

is( $code,
      <<"EOPERL",
package TEST;
# This module was generated automatically by ExtUtils::H2PM from t/01constant.t

push \@EXPORT_OK, 'DEFINED_CONSTANT';
use constant DEFINED_CONSTANT => 10;

1;
EOPERL
      'Simple constant' );

ok( evalordie("no strict; $code"), 'Code evaluates successfully' );

$INC{"TEST.pm"} = '$code';

is( evalordie("TEST::DEFINED_CONSTANT()" ),
    10,
    'Code exports a constant of the right value' );

$code = stdout_from {
         module "TEST";
         include "t/test.h", local => 1;
         no_export;
         constant "DEFINED_CONSTANT";
         write_perl;
      };

is( $code,
      <<"EOPERL",
package TEST;
# This module was generated automatically by ExtUtils::H2PM from t/01constant.t

use constant DEFINED_CONSTANT => 10;

1;
EOPERL
      'No-export constant' );

$code = stdout_from {
         module "TEST";
         include "t/test.h", local => 1;
         constant "ENUMERATED_CONSTANT";
         write_perl;
      };

is( $code,
      <<"EOPERL",
package TEST;
# This module was generated automatically by ExtUtils::H2PM from t/01constant.t

use constant ENUMERATED_CONSTANT => 20;

1;
EOPERL
      'Enumerated constant' );

$code = stdout_from {
         module "TEST";
         include "t/test.h", local => 1;
         constant "STATIC_CONSTANT";
         write_perl;
      };

is( $code,
      <<"EOPERL",
package TEST;
# This module was generated automatically by ExtUtils::H2PM from t/01constant.t

use constant STATIC_CONSTANT => 30;

1;
EOPERL
      'Static constant' );
