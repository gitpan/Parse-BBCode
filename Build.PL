use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    create_makefile_pl => 'traditional',
    license            => 'perl',
    module_name        => 'Parse::BBCode',
    dist_author        => 'Tina Mueller',
    requires => {
        'URI::Escape' => 0,
        Carp           => 0,
        strict         => 0,
        warnings       => 0,
        'Data::Dumper' => 0,
        'Class::Accessor::Fast' => 0,
        perl => '5.6.1',
    },
    build_requires => {
        'Test::More'          => 0,
    },
    recommends         => {
    },
    create_readme      => 1,
    sign               => 1,
);
$build->create_build_script;
