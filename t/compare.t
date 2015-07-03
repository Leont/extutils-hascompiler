#! perl

use strict;
use warnings;

use Test::More;
use ExtUtils::HasCompiler ':all';

if (eval { require ExtUtils::CBuilder}) {
	plan tests => 1;
	my @warnings;
	local $SIG{__WARN__} = sub { push @warnings, @_ };
	is(can_compile_loadable_object(), ExtUtils::CBuilder->new->have_compiler, 'Have a C compiler if CBuilder agrees') or diag(@warnings);
}
else {
	plan skip_all => 'Can\'t compare to CBuilder without CBuilder';
}

