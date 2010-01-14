#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2010 -- leonerd@leonerd.org.uk

package ExtUtils::H2PM;

use strict;
use warnings;

our $VERSION = '0.01';

use Exporter 'import';
our @EXPORT = qw(
   module
   include
   constant

   structure
      member_numeric

   no_export use_export use_export_ok

   write_perl
);

use ExtUtils::CBuilder;

=head1 NAME

C<ExtUtils::H2PM> - automatically generate perl modules to wrap C header files

=head1 DESCRIPTION

This module assists in generating wrappers around system functionallity, such
as C<socket()> types or C<ioctl()> calls, where the only interesting features
required are the values of some constants or layouts of structures normally
only known to the C header files. Rather than writing an entire XS module just
to contain some constants and pack/unpack functions, this module allows the
author to generate, at module build time, a pure perl module containing
constant declarations and structure utility functions. The module then
requires no XS module to be loaded at run time.

In comparison to F<h2ph>, C<C::Scan::Constants>, and so on, this module works
by generating a small C program containing C<printf()> lines to output the
values of the constants, compiling it, and running it. This allows it to
operate without needing tricky syntax parsing or guessing of the contents of
C header files.

It can also automatically build pack/unpack functions for simple structure
layouts, whose members are all simple integer fields. It is not intended as a
full replacement of arbitrary code written in XS modules. If structures should
contain pointers, or require special custom handling, then likely an XS module
will need to be written.

=cut

my @preamble;
my @fragments;

my $done_carp;
my @genblocks;

my $export_mode; use_export_ok();
my @exports; my @exports_ok;

=head1 FUNCTIONS

=cut

sub push_export
{
   my $name = shift;

   if( $export_mode eq "OK" ) {
      push @exports_ok, $name;
   }
   elsif( $export_mode ) {
      push @exports, $name;
   }
}

=head2 module $name

Sets the name of the perl module to generate. This will apply a C<package>
header.

=cut

my $modulename;
sub module
{
   $modulename = shift;

   print gen_perl() if @fragments;

   print "package $modulename;\n" .
         "# This module was generated automatically by ExtUtils::H2PM from $0\n" .
         "\n";

   undef $done_carp;
}

=head2 include $file

Adds a file to the list of headers which will be included by the C program, to
obtain the constants or structures from

=cut

sub include
{
   my ( $file, %params ) = @_;

   # undocumented but useful for testing
   if( $params{local} ) {
      push @preamble, qq[#include "$file"];
   }
   else {
      push @preamble, "#include <$file>";
   }
}

=head2 constant $name

Adds a numerical constant.

=cut

sub constant
{
   my $name = shift;

   push @fragments, qq{  printf("$name=%ld\\n", (long)$name);};

   push @genblocks, [ $name => sub {
      my ( $result ) = @_;
      "use constant $name => $result;";
   } ];

   push_export $name;
}

=head2 structure $name, %args

Adds a structure definition. This requires a named argument, C<members>. This
should be an ARRAY ref containing an even number of name-definition pairs. The
first of each pair should be a member name. The second should be one of the
following structure member definitions.

The following additional named arguments are also recognised:

=over 8

=item * pack_func => STRING

=item * unpack_func => STRING

Use the given names for the generated pack or unpack functions.

=back

=cut

sub structure
{
   my ( $name, %params ) = @_;

   ( my $basename = $name ) =~ s/^struct //;

   my $packfunc   = $params{pack_func}   || "pack_$basename";
   my $unpackfunc = $params{unpack_func} || "unpack_$basename";

   my @membernames;
   my @memberhandlers;

   my @members = @{ $params{members} };
   for( my $i = 0; $i < @members; $i+=2 ) {
      my ( $memname, $handler ) = @members[$i,$i+1];

      push @membernames, $memname;
      push @memberhandlers, $handler;

      $handler->{set_names}->( $basename, $memname );
   }

   my $argindex = 0;
   foreach my $handler ( @memberhandlers ) {
      $handler->{set_arg}( $argindex );
   }

   push @fragments,
      "  {",
      "    $name $basename;", 
    qq[    printf("$basename=");],
      ( map { "    " . $_->{gen_c}->() } @memberhandlers ),
    qq[    printf("\\n");],
      "  }";

   push @genblocks, [ $basename => sub {
      my ( $result ) = @_;

      my $curpos = 0;

      my $format = "";

      foreach my $def ( split m/,/, $result ) {
         my $handler = shift @memberhandlers;

         $format .= $handler->{gen_format}( $def, $curpos ) . " ";
      }

      my $len = $curpos;
      my $members = join( ", ", @membernames );

      my $carp = $done_carp++ ? "" : "use Carp;\n";

      $carp . join( "\n",
         "",
         "sub $packfunc",
         "{",
       qq[   \@_ == $argindex or croak "usage: $packfunc($members)";],
       qq[   pack "$format", \@_;],
         "}",
         "",
         "sub $unpackfunc",
         "{", 
       qq[   length \$_[0] == $len or croak "$unpackfunc: expected $len bytes";],
       qq[   unpack "$format", \$_[0];],
         "}" );
   } ];

   push_export $packfunc;
   push_export $unpackfunc;
}

=pod

The following structure member definitions are allowed:

=over 8

=cut

my %struct_formats = (
   map {
      my $bytes = length( pack "$_", 0 );
      "${bytes}u" => uc $_,
      "${bytes}s" => lc $_
   } qw( C S L )
);

if( eval { pack "Q", 0 } ) {
   my $bytes = length( pack "Q", 0 );
   $struct_formats{"${bytes}u"} = "Q";
   $struct_formats{"${bytes}s"} = "q";
}

=item * member_numeric

The field contains a single signed or unsigned number. Its size and signedness
will be automatically detected.

=cut

sub member_numeric
{
   my $self = shift;

   my $varname;
   my $membername;
   my $argindex;

   return {
      set_names => sub { ( $varname, $membername ) = @_; },
      set_arg => sub { $argindex = $_[0]++; },

      gen_c => sub {
         qq{printf("$membername@%d+%d%c,", } . 
            "((void*)&$varname.$membername-(void*)&$varname), " . # offset
            "sizeof($varname.$membername), " .                    # size
            "($varname.$membername=-1)<0?'s':'u'" .               # signedness
            ");";
      },
      gen_format => sub {
         my ( $def ) = @_;
         #  ( undef, curpos ) = @_;

         my ( $member, $offs, $size, $sign ) = $def =~ m/^(\w+)@(\d+)\+(\d+)([us])$/;

         my $format = "";
         if( $offs > $_[1] ) {
            my $pad = $offs - $_[1];

            $format .= "x" x $pad;
            $_[1] += $pad;
         }
         elsif( $offs < $_[1] ) {
            die "Err.. need to go backwards for structure $varname member $member";
         }

         $format .= $struct_formats{"$size$sign"};
         $_[1] += $size;

         return $format;
      },
   };
}

=back

The structure definition results in two new functions being created,
C<pack_$name> and C<unpack_$name>, where C<$name> is the name of the structure
(with the leading C<struct> prefix stripped). These behave similarly to the
familiar functions such as C<pack_sockaddr_in>; the C<pack_> function will
take a list of fields and return a packed string, the C<unpack_> function will
take a string and return a list of fields.

=cut

=head2 no_export, use_export, use_export_ok

Controls the export behaviour of the generated symbols. C<no_export> creates
symbols that are not exported by their package, they must be used fully-
qualified. C<use_export> creates symbols that are exported by default.
C<use_export_ok> creates symbols that are exported if they are specifically
requested at C<use> time.

The mode can be changed at any time to affect only the symbols that follow
it. It defaults to C<use_export_ok>.

=cut

sub no_export     { $export_mode = 0 }
sub use_export    { $export_mode = 1 }
sub use_export_ok { $export_mode = "OK" }

my $cbuilder = ExtUtils::CBuilder->new( quiet => 1 );

sub gen_perl
{
   return "" unless @fragments;

   my $c_file = join "\n",
      "#include <stdio.h>",
      @preamble,
      "",
      "int main(void) {",
      @fragments,
      "  return 0;",
      "}";

   undef @preamble;
   undef @fragments;

   die "Cannot generate a C file yet - no module name\n" unless defined $modulename;

   my $tempname = "gen-$modulename";

   my $sourcename = "$tempname.c";
   {
      open( my $source_fh, "> $sourcename" ) or die "Cannot write $sourcename - $!";
      print $source_fh $c_file;
   }

   my $objname = eval { $cbuilder->compile( source => $sourcename ) };

   unlink $sourcename;

   if( !defined $objname ) {
      die "Failed to compile source\n";
   }

   my $exename = eval { $cbuilder->link_executable( objects => $objname ) };

   unlink $objname;

   if( !defined $exename ) {
      die "Failed to link executable\n";
   }

   my $output;
   {
      open( my $runh, "./$exename |" ) or die "Cannot pipeopen $exename - $!";

      local $/;
      $output = <$runh>;
   }

   unlink $exename;

   my %results = map { m/^(\w+)=(.*)$/ } split m/\n/, $output;

   my $perl = "";

   if( @exports ) {
      $perl .= "push \@EXPORT, " . join( ", ", map { "'$_'" } @exports ) . ";\n";
      undef @exports;
   }

   if( @exports_ok ) {
      $perl .= "push \@EXPORT_OK, " . join( ", ", map { "'$_'" } @exports_ok ) . ";\n";
      undef @exports_ok;
   }

   foreach my $genblock ( @genblocks ) {
      my ( $key, $code ) = @$genblock;

      $perl .= $code->( $results{$key} ) . "\n";
   }

   undef @genblocks;

   return $perl;
}

sub write_perl
{
   print gen_perl . "\n1;\n";
}

# Redirect STDOUT as EU::MM / M::B has directed us
if( @ARGV ) {
   open( STDOUT, ">", $ARGV[0] ) or die "Cannot write '$ARGV[0]' - $!";
}

END { write_perl if @fragments }

# Keep perl happy; keep Britain tidy
1;

=head1 EXAMPLES

Normally this module would be used by another module at build time, to
construct the relevant constants and structure functions from system headers.

For example, suppose your operating system defines a new type of socket, which
has its own packet and address families, and perhaps some new socket options
which are valid on this socket. We can build a module to contain the relevant
constants and structure functions by writing, for example:

 #!/usr/bin/perl

 use ExtUtils::H2PM;
 
 module "Socket::Moonlazer";

 include "moon/lazer.h";

 constant "AF_MOONLAZER";
 constant "PF_MOONLAZER";

 constant "SOL_MOONLAZER";

 constant "MOONLAZER_POWER";
 constant "MOONLAZER_WAVELENGTH";

 structure "struct lazerwl",
    members => [
       lwl_nm_coarse => member_numeric,
       lwl_nm_fine   => member_numeric,
    ];

If we save this script as, say, F<lib/Socket/Moonlazer.pm.PL>, then when
C<ExtUtils::MakeMaker> or C<Module::Build> come to build the module, they will
execute the script, and capture its output to store as
F<lib/Socket/Moonlazer.pm>. Once installed, any other code can simply

 use Socket::Moonlazer qw( AF_MOONLAZER );

to import a constant.

The method described above doesn't allow us any room to actually include other
code in the module. Perhaps, as well as these simple constants, we'd like to
include functions, documentation, etc... To allow this, name the script
instead something like F<lib/Socket/Moonlazer_const.pm.PL>, so that this is
the name used for the generated output. The code can then be included in the
actual F<lib/Socket/Moonlazer.pm> (which will just be a normal perl module) by

 package Socket::Moonlazer;

 use Socket::Moonlazer_const;

 sub get_power
 {
    getsockopt( $_[0], SOL_MOONLAZER, MOONLAZER_POWER );
 }

 sub set_power
 {
    setsockopt( $_[0], SOL_MOONLAZER, MOONLAZER_POWER, $_[1] );
 }

 sub get_wavelength
 {
    my $wl = getsockopt( $_[0], SOL_MOONLAZER, MOONLAZER_WAVELENGTH );
    defined $wl or return;
    unpack_lazerwl( $wl );
 }

 sub set_wavelength
 {
    my $wl = pack_lazerwl( $_[1], $_[2] );
    setsockopt( $_[0], SOL_MOONLAZER, MOONLAZER_WAVELENGTH, $wl );
 }

 1;

Sometimes, the actual C structure layout may not exactly match the semantics
we wish to present to perl modules using this extension wrapper. Socket
address structures typically contain their address family as the first member,
whereas this detail isn't exposed by, for example, the C<sockaddr_in> and
C<sockaddr_un> functions. To cope with this case, the low-level structure
packing and unpacking functions can be generated with a different name, and
wrapped in higher-level functions in the main code. For example, in
F<Moonlazer_const.pm.PL>:

 no_export;

 structure "struct sockaddr_ml",
    pack_func   => "_pack_sockaddr_ml",
    unpack_func => "_unpack_sockaddr_ml",
    members => [
       ml_family    => member_numeric,
       ml_lat_deg   => member_numeric,
       ml_long_deg  => member_numeric,
       ml_lat_fine  => member_numeric,
       ml_long_fine => member_numeric,
    ];

This will generate a pack/unpack function pair taking or returning five
arguments; these functions will not be exported. In our main F<Moonlazer.pm>
file we can wrap these to actually expose a different API:

 sub pack_sockaddr_ml
 {
    @_ == 2 or croak "usage: pack_sockaddr_ml(lat, long)";
    my ( $lat, $long ) = @_;

    return _pack_sockaddr_ml( AF_MOONLAZER, int $lat, int $long,
      ($lat - int $lat) * 1_000_000, ($long - int $long) * 1_000_000);
 }

 sub unpack_sockaddr_ml
 {
    my ( $family, $lat, $long, $lat_fine, $long_fine ) =
       _unpack_sockaddr_ml( $_[0] );

    $family == AF_MOONLAZER or croak "expected family AF_MOONLAZER";

    return ( $lat + $lat_fine/1_000_000, $long + $long_fine/1_000_000 );
 }

=head1 TODO

=over 4

=item *

Consider more flexible structure members. Perhaps string-like members that
wrap fixed-size C<char> arrays. With strings comes the requirement to have
members that store a size. This requires cross-referential members. And while
we're at it it might be nice to have constant members; fill in constants
without consuming arguments when packing, assert the right value on unpacking.

=back

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>