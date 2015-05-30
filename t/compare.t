#! perl

use strict;
use warnings;

use Test::More;
use ExtUtils::HasCompiler ':all';

if (eval { require ExtUtils::CBuilder}) {
	plan tests => 1;
	is(can_compile_loadable_object(), ExtUtils::CBuilder->new->have_compiler, 'Have a C compiler if CBuilder agrees');
}
else {
	plan skip_all => 'Can\'t compare to CBuilder without CBuilder';
}

