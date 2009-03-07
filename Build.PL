use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Class::Std::Slots',
    sign                => 1,
    license             => 'perl',
    dist_author         => 'Andy Armstrong <andy@hexten.net>',
    dist_version_from   => 'lib/Class/Std/Slots.pm',
    requires => {
        'Test::More' => 0,
        'Class::Std' => 0, 
        'version'    => 0,
    },
    add_to_cleanup      => [ 'Class-Std-Slots-*' ],
);

$builder->create_build_script();
