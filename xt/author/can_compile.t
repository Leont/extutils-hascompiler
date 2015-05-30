#! perl

use Test::More tests => 2;
use ExtUtils::HasCompiler ':all';

ok(can_compile_executable(), 'Can compile an executable');
ok(can_compile_loadable_object(), 'Can compile a loadable object');

