#! perl

use Test::More; 0.89;
use ExtUtils::HasCompiler ':all';

ok(can_compile_executable(), 'Can compile an executable');
ok(can_compile_loadable_object(), 'Can compile a loadable object');

done_testing;

