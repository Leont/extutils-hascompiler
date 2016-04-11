#! perl

use strict;
use warnings;

use Test::More 0.82 tests => 1;
use ExtUtils::HasCompiler ':all';
use File::Temp 'tempfile';

use Config;
use Cwd;
use IPC::Open3;
use File::Path 'mkpath';
use File::Spec::Functions qw/catfile catdir devnull/;
use File::Temp 'tempdir';

my $Makefile_PL = <<'END';
use ExtUtils::MakeMaker;
WriteMakefile(NAME => 'EUHC::Test');
END

my $PM_file = <<'END';
package EUHC::Test;
require XSLoader;
XSLoader::load(__PACKAGE__);
END

my $XS_file = <<'END';
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = EUHC::Test PACKAGE = EUHC::Test
PROTOTYPES: DISABLED

IV
compiled_xs()
	PPCODE:
	XSRETURN_IV(1);
END

my $test_file = <<'END';
use Test::More tests => 1;
use EUHC::Test;
ok EUHC::Test::compiled_xs(), 'compiled_xs returns true';
END

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };
my $output;
my $filename = $] >= 5.008 ? \$output : devnull;
open my $fh, '>', $filename;
my $can_compile = can_compile_loadable_object(output => $fh);
note($output);
my $can = $can_compile ? 'can' : "can't";
is($can_compile, compile_with_mm(), "MakeMaker agrees we $can compile") or diag(@warnings);

sub compile_with_mm {
	my $cwd = cwd;
	my $ret = eval {
		local $SIG{__DIE__} = sub { warn $_[0] };
		chdir tempdir(CLEANUP => 1);
		write_file('Makefile.PL', $Makefile_PL);
		mkpath(catdir(qw/lib EUHC/));
		write_file(catfile(qw/lib EUHC Test.pm/), $PM_file);
		write_file('Test.xs', $XS_file);
		mkdir('t');
		write_file(catfile(qw/t compiled.t/), $test_file);

		capture($^X, "Makefile.PL");
		capture($Config{make});
		capture($Config{make}, 'test');
		return 1;
	};
	chdir $cwd;
	return $ret;
}

sub write_file {
	my ($filename, $content) = @_;
	open my $fh, '>', $filename or die "Couldn't open file $filename: $!";
	print $fh $content or die "Couldn't write to file: $!";
	close $fh or die "Couldn't close file: $!";
}

sub capture {
	my @args = @_;
	my $pid = open3(my $in, my $out, undef, @args);
	close $in;
	my $output = do { local $/; <$out> };
	waitpid $pid, 0 or die "Couldn't wait for @args: $!";
	die "Couldn't run @args: $output" if $? != 0;
	note($output);
}
