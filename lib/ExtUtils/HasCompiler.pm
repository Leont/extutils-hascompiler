package ExtUtils::HasCompiler;

use strict;
use warnings;

use Exporter 5.57 'import';
our @EXPORT = qw/can_compile_executable can_compile_loadable_object/;

use Config;
use Carp 'croak';
use Env '@PATH';
use File::Basename 'basename';
use File::Spec::Functions qw/curdir catdir rel2abs/;
use File::Temp qw/tempdir tempfile/;
use Perl::OSType 'is_os_type';

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
	my (%args) = @_;

	my $tempdir = tempdir(DIR => curdir, CLEANUP => 1);
	my ($source_handle, $source_name) = tempfile(DIR => $tempdir, SUFFIX => '.c');
	write_file($source_handle, $executable_code);

	my $config = $args{config} || 'ExtUtils::HasCompiler::Config';
	my ($cc, $ccflags, $ldflags, $libs) = map { $args{$_} || $config->get($_) } qw/cc ccflags ldflags libs/;
	my $executable = catdir($tempdir, basename($source_name, '.c') . $config->get('_exe'));

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
	system($command) and return;
	return not system(rel2abs($executable));
}

my $loadable_object_code = <<'END';
#include <stdlib.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C"
#else
extern
#endif

void foo() {
	puts("It seems we've got a working compiler");
}
END

sub can_compile_loadable_object {
	my (%args) = @_;

	my $tempdir = tempdir(DIR => curdir, CLEANUP => 1);
	my ($source_handle, $source_name) = tempfile(DIR => $tempdir, SUFFIX => '.c');
	write_file($source_handle, $loadable_object_code);

	my $config = $args{config} || 'ExtUtils::HasCompiler::Config';
	my ($cc, $ccflags, $cccdlflags, $lddlflags, $libs) = map { $args{$_} || $config->get($_) } qw/cc ccflags cccdlflags lddlflags libs/;
	my $loadable_object = catdir($tempdir, basename($source_name, '.c') . '.' . $config->get('dlext'));

	my $command;
	if (is_os_type('Unix') || $Config{gccversion}) {
		$command = "$cc $ccflags $cccdlflags $lddlflags -o $loadable_object $source_name";
	}
	elsif (is_os_type('Windows') && $config->get('cc') =~ /^cl/) {
		$command = "$cc $ccflags -Fe$loadable_object $source_name -link $lddlflags $libs";
	}
	else {
		warn "Unsupported system: can't test compiler availability. Patches welcome...";
		return;
	}

	print "$command\n" if not $args{quiet};
	system($command) and die return;

	require DynaLoader;
	my $handle = DynaLoader::dl_load_file($loadable_object, 0);
	if ($handle) {
		my $ret = DynaLoader::dl_find_symbol($handle, 'foo');
		DynaLoader::dl_unload_file($handle);
		return !!$ret;
	}
	return;
}

sub ExtUtils::HasCompiler::Config::get {
	my (undef, $key) = @_;
	return $Config{$key};
}

1;

# ABSTRACT: Check for the presence of a compiler
