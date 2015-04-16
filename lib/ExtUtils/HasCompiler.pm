package ExtUtils::HasCompiler;

use strict;
use warnings;

use Exporter 5.57 'import';
our @EXPORT_OK = qw/can_compile_executable can_compile_loadable_object/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

use Config;
use Carp 'croak';
use File::Basename 'basename';
use File::Spec::Functions qw/curdir catfile catdir rel2abs/;
use File::Temp qw/tempdir tempfile/;
use Perl::OSType 'is_os_type';

my $tempdir = tempdir(CLEANUP => 1);

sub write_file {
	my ($fh, $content) = @_;
	print $fh $content or croak "Couldn't write to file: $!";
	close $fh or croak "Couldn't close file: $!";
}

my $executable_code = <<'END';
#include <stdlib.h>
#include <stdio.h>

int main(int argc, char** argv) {
	puts("It seems we've got a working compiler");
	return 0;
}
END

sub can_compile_executable {
	my %args = @_;

	my ($source_handle, $source_name) = tempfile(DIR => $tempdir, SUFFIX => '.c');
	write_file($source_handle, $executable_code);

	my $config = $args{config} || 'ExtUtils::HasCompiler::Config';
	my ($cc, $ccflags, $ldflags, $libs) = map { $args{$_} || $config->get($_) } qw/cc ccflags ldflags libs/;
	my $executable = catfile($tempdir, basename($source_name, '.c') . $config->get('_exe'));

	my $command;
	if (is_os_type('Unix') || $Config{gccversion}) {
		$command = "$cc $ccflags -o $executable $source_name $ldflags";
	}
	elsif (is_os_type('Windows') && $config->get('cc') =~ /^cl/) {
		$command = "$cc $ccflags -Fe$executable $source_name -link $ldflags $libs";
	}
	else {
		warn "Unsupported system: can't test compiler availability. Patches welcome...";
		return;
	}

	print "$command\n" if not $args{quiet};
	system $command and return;
	return not system(rel2abs($executable));
}

my $loadable_object_format = <<'END';
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

XS(exported) {
#ifdef dVAR
	dVAR;
#endif
	dXSARGS;

	PERL_UNUSED_VAR(cv); /* -W */
	PERL_UNUSED_VAR(items); /* -W */

	XSRETURN_IV(42);
}

#ifndef XS_EXTERNAL
#define XS_EXTERNAL(foo) XS(foo)
#endif

XS_EXTERNAL(boot_%s) {
#ifdef dVAR
	dVAR;
#endif
	dXSARGS;

	PERL_UNUSED_VAR(cv); /* -W */
	PERL_UNUSED_VAR(items); /* -W */

	newXS("%s::exported", exported, __FILE__);
}

END

my $counter = 1;

sub can_compile_loadable_object {
	my %args = @_;

	my ($source_handle, $source_name) = tempfile(DIR => $tempdir, SUFFIX => '.c', UNLINK => 1);
	my $basename = basename($source_name, '.c');

	my $shortname = '_Loadable' . $counter++;
	my $package = "ExtUtils::HasCompiler::$shortname";
	my $loadable_object_code = sprintf $loadable_object_format, $basename, $package;
	write_file($source_handle, $loadable_object_code);

	my $config = $args{config} || 'ExtUtils::HasCompiler::Config';
	my ($cc, $ccflags, $optimize, $cccdlflags, $lddlflags, $perllibs, $archlibexp) = map { $args{$_} || $config->get($_) } qw/cc ccflags optimize cccdlflags lddlflags perllibs archlibexp/;
	my $incdir = catdir($archlibexp, 'CORE');

	my $loadable_object = catfile($tempdir, $basename . '.' . $config->get('dlext'));

	my $command;
	if (is_os_type('Unix') || $config->get('gccversion')) {
		if ($^O eq 'aix') {
			$lddlflags =~ s/\Q$(BASEEXT)\E/$basename/;
			$lddlflags =~ s/\Q$(PERL_INC)\E/$incdir/;
		}
		$command = qq{$cc $ccflags "-I$incdir" $cccdlflags $lddlflags $perllibs -o $loadable_object $source_name};
	}
	elsif (is_os_type('Windows') && $config->get('cc') =~ /^cl/) {
		require ExtUtils::Mksymlists;
		ExtUtils::Mksymbols::Mksymbols(NAME => $basename);
		$command = "$cc $ccflags $optimize $source_name $basename.def /link $lddlflags $perllibs /out:$loadable_object";
	}
	else {
		warn "Unsupported system: can't test compiler availability. Patches welcome...";
		return;
	}

	print "$command\n" if not $args{quiet};
	system $command and die "Couldn't execute command: $!";

	require DynaLoader;
	my $handle = DynaLoader::dl_load_file($loadable_object, 0);
	if ($handle) {
		my $symbol = DynaLoader::dl_find_symbol($handle, "boot_$basename");
		my $compilet = DynaLoader::dl_install_xsub('__ANON__::__ANON__', $symbol, $source_name);
		my $ret = eval { $compilet->(); $package->exported };
		delete $ExtUtils::HasCompiler::{"$shortname\::"};
		DynaLoader::dl_unload_file($handle);
		return $ret == 42;
	}
	return;
}

sub ExtUtils::HasCompiler::Config::get {
	my (undef, $key) = @_;
	return $Config{$key};
}

1;

# ABSTRACT: Check for the presence of a compiler
