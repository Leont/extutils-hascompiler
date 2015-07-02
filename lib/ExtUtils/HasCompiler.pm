package ExtUtils::HasCompiler;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw/can_compile_loadable_object/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

use Config;
use Carp 'carp';
use File::Basename 'basename';
use File::Spec::Functions qw/catfile catdir/;
use File::Temp qw/tempdir tempfile/;

my $tempdir = tempdir(CLEANUP => 1);

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

/* we don't want to mess with .def files on mingw */
#if defined(WIN32) && defined(__GNUC__)
#  define EXPORT __declspec(dllexport)
#else
#  define EXPORT
#endif

EXPORT XS_EXTERNAL(boot_%s) {
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

	my $config = $args{config} || 'ExtUtils::HasCompiler::Config';
	return if not $config->get('usedl');

	my ($source_handle, $source_name) = tempfile(DIR => $tempdir, SUFFIX => '.c', UNLINK => 1);
	my $basename = basename($source_name, '.c');

	my $shortname = '_Loadable' . $counter++;
	my $package = "ExtUtils::HasCompiler::$shortname";
	printf $source_handle $loadable_object_format, $basename, $package or do { carp "Couldn't write to $source_name: $!"; return };
	close $source_handle or do { carp "Couldn't close $source_name: $!"; return };

	my ($cc, $ccflags, $optimize, $cccdlflags, $lddlflags, $libperl, $perllibs, $archlibexp) = map { $config->get($_) } qw/cc ccflags optimize cccdlflags lddlflags libperl perllibs archlibexp/;
	my $incdir = catdir($archlibexp, 'CORE');

	my $loadable_object = catfile($tempdir, $basename . '.' . $config->get('dlext'));

	my @commands;
	if ($^O eq 'MSWin32' && $cc =~ /^cl/) {
		require ExtUtils::Mksymlists;
		my $abs_basename = catfile($tempdir, $basename);
		#Mksymlists will add the ext on its own
		ExtUtils::Mksymlists::Mksymlists(NAME => $basename, FILE => $abs_basename);
		push @commands, qq{$cc $ccflags $optimize /I "$incdir" $source_name $abs_basename.def /Fo$abs_basename.obj /Fd$abs_basename.pdb /link $lddlflags $libperl $perllibs /out:$loadable_object};
	}
	elsif ($^O eq 'VMS') {
		carp "VMS is currently unsupported";
		return;
	}
	else {
		my $extra = $^O eq 'MSWin32' ? '-l' . ($libperl =~ /lib([^.]+)\./)[0]
			: $^O eq 'cygwin' ? catfile($incdir, $config->get('useshrplib') ? 'libperl.dll.a' : 'libperl.a')
			: '';
		if ($^O eq 'aix') {
			$lddlflags =~ s/\Q$(BASEEXT)\E/$basename/;
			$lddlflags =~ s/\Q$(PERL_INC)\E/$incdir/;
		}
		push @commands, qq{$cc $ccflags "-I$incdir" $cccdlflags $source_name $lddlflags $extra $perllibs -o $loadable_object };
	}

	for my $command (@commands) {
		print "$command\n" if not $args{quiet};
		system $command and do { carp "Couldn't execute $command: $!"; return };
	}

	# Skip loading when cross-compiling
	return 1 if exists $args{skip_load} ? $args{skip_load} : $config->get('usecrosscompile');

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
	return $ENV{uc $key} || $Config{$key};
}

1;

# ABSTRACT: Check for the presence of a compiler

=head1 DESCRIPTION

This module tries to check if the current system is capable of compiling, linking and loading an XS module.

B<Notice>: this is an early release, interface stability isn't guaranteed yet.

=func can_compile_loadable_object(%opts)

This checks if the system can compile, link and load a perl loadable object. It may take the following options:

=over 4

=item * quiet

Do not output the executed compilation commands.

=item * config

An L<ExtUtils::Config|ExtUtils::Config> (compatible) object for configuration.

=item * skip_load

This causes can_compile_loadable_object to not try to load the generated object. This defaults to true on a cross-compiling perl.

=back
