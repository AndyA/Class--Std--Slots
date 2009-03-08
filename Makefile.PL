use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  ( MM->can( 'signature_target' ) ? ( SIGN => 1 ) : () ),
  license( 'perl' ),
  NAME          => 'Class::Std::Slots',
  AUTHOR        => 'Andy Armstrong <andy@hexten.net>',
  VERSION_FROM  => 'lib/Class/Std/Slots.pm',
  ABSTRACT_FROM => 'lib/Class/Std/Slots.pm',
  PL_FILES      => {},
  PREREQ_PM     => {
    'Test::More' => 0,
    'Class::Std' => 0,
  },
  dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
  clean => { FILES    => 'Class-Std-Slots-*' },
);

sub license {
  my $lic = shift;
  local $^W = 0;    # Silence warning about non-numeric version
  return
   unless $ExtUtils::MakeMaker::VERSION >= '6.31';
  return ( LICENSE => $lic );
}
