#!/usr/bin/perl -w

use strict;
use Test::More tests => 6;

use ExtUtils::H2PM;

use constant LITTLE_ENDIAN => (pack("s",1) eq "\1\0");
use constant BIG_ENDIAN    => (pack("s",1) eq "\0\1");
BEGIN { LITTLE_ENDIAN or BIG_ENDIAN or die "Cannot determine platform endian" }

sub evalordie
{
   my $code = shift;
   my $ret = eval $code;
   $@ and die $@;
   $ret;
}

my $code;

$code = do {
         module "TEST";
         include "t/test.h", local => 1;
         structure "struct point",
            members => [
               x => member_numeric,
               y => member_numeric,
            ];
         gen_output;
      };

is_deeply( [ split m/\n/, $code ],
    [ split m/\n/, <<"EOPERL" ],
package TEST;
# This module was generated automatically by ExtUtils::H2PM from $0

push \@EXPORT_OK, 'pack_point', 'unpack_point';
use Carp;

sub pack_point
{
   \@_ == 2 or croak "usage: pack_point(x, y)";
   pack "l l ", \@_;
}

sub unpack_point
{
   length \$_[0] == 8 or croak "unpack_point: expected 8 bytes";
   unpack "l l ", \$_[0];
}

1;
EOPERL
      'Simple structure' );

ok( evalordie("no strict; $code"), 'Code evaluates successfully' );

$INC{"TEST.pm"} = '$code';

is( TEST::pack_point(0x1234,0x5678),
    BIG_ENDIAN ? "\0\0\x12\x34\0\0\x56\x78" : "\x34\x12\0\0\x78\x56\0\0",
    'pack_point()' );

is_deeply( [ TEST::unpack_point( BIG_ENDIAN ? "\0\0\x12\x34\0\0\x56\x78" : "\x34\x12\0\0\x78\x56\0\0" ) ],
   [ 0x1234, 0x5678 ],
   'unpack_point()' );

$code = do {
         module "TEST";
         include "t/test.h", local => 1;
         structure "struct point",
            pack_func => "point_packing_function",
            unpack_func => "point_unpacking_function",
            members => [
               x => member_numeric,
               y => member_numeric,
            ];
         gen_output;
      };

is_deeply( [ split m/\n/, $code ],
    [ split m/\n/, <<"EOPERL" ],
package TEST;
# This module was generated automatically by ExtUtils::H2PM from $0

push \@EXPORT_OK, 'point_packing_function', 'point_unpacking_function';
use Carp;

sub point_packing_function
{
   \@_ == 2 or croak "usage: point_packing_function(x, y)";
   pack "l l ", \@_;
}

sub point_unpacking_function
{
   length \$_[0] == 8 or croak "point_unpacking_function: expected 8 bytes";
   unpack "l l ", \$_[0];
}

1;
EOPERL
      'Structure with different function names' );

$code = do {
         module "TEST";
         include "t/test.h", local => 1;
         structure "struct msghdr",
            members => [
               cmd  => member_numeric,
               vers => member_numeric,
            ];
         gen_output;
      };

is_deeply( [ split m/\n/, $code ],
    [ split m/\n/, <<"EOPERL" ],
package TEST;
# This module was generated automatically by ExtUtils::H2PM from $0

push \@EXPORT_OK, 'pack_msghdr', 'unpack_msghdr';
use Carp;

sub pack_msghdr
{
   \@_ == 2 or croak "usage: pack_msghdr(cmd, vers)";
   pack "l c x3", \@_;
}

sub unpack_msghdr
{
   length \$_[0] == 8 or croak "unpack_msghdr: expected 8 bytes";
   unpack "l c x3", \$_[0];
}

1;
EOPERL
      'Structure with trailing padding' );
