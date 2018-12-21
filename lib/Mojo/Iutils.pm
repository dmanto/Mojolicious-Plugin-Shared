package Mojo::Iutils;
use Mojo::Base 'Mojo::EventEmitter', -signatures;

use Carp 'croak';
use Fcntl ':flock';
use File::Spec::Functions 'tmpdir';
use Mojo::File 'path';
use Mojo::Util;
use Encode qw/decode encode/;
use constant {
	IUTILS_DIR => 'mojo_iutils_',
	DEBUG => $ENV{MOJO_IUTILS_DEBUG} || 0,
	VARS_DIR => 'vars',
	LOCKS_DIR => 'locks',
	PUBSUBS_DIR => 'pubsubs',
	QUEUES_DIR => 'queues',
    CATCH_VALID_TO => 5,
    CATCH_SAFE_WINDOW => 5
};

has base_dir => sub {
	path(tmpdir, IUTILS_DIR.(eval {scalar getpwuid($<)} || getlogin || 'nobody'))->to_string;
};

our $VERSION = '0.01';

my ($varsdir, $queuesdir, $pubsubsdir, $semaphore_file);
my $valid_fname = qr/^[\w\.-]+$/;
my %catched;


sub istash {
	my ($self, $key, $arg) = @_;
	my ($cb, $val, $has_to_read, $has_to_write);
	die "Key $key not valid" unless $key =~ $valid_fname;
	if (ref $arg eq 'CODE') {
		$cb = $arg;
		$has_to_read = $has_to_write = 1;
	} elsif (@_ % 2) {
		$val = $arg;
		$has_to_write = 1;
	} else {
		$has_to_read = 1;
	}
	unless (exists $catched{$key}) {
		unless ($varsdir) { # inicializes $varsdir & $semaphore_file
			$varsdir = path($self->base_dir, VARS_DIR );
			$varsdir->make_path unless -d $varsdir;
			$semaphore_file = $varsdir->child('semaphore.lock')->to_string;
		}


		my $file = $varsdir->child($key)->to_string;
		open(my $sf, '>', $semaphore_file) or die "Couldn't open $semaphore_file for write: $!";
		flock($sf, LOCK_EX) or die "Couldn't lock $semaphore_file: $!";
		unless (-f $file){
			open my $tch, '>', $file or die "Couldn't touch $file: $!";
			close($tch) or die "Couldn't close $file: $!";
		}
		close($sf) or die "Couldn't close $semaphore_file: $!";
		$catched{$key}{path} = $file;
	}


	my $fname = $catched{$key}{path}; # path to file
	my $lock_flags = $has_to_write ? LOCK_EX : LOCK_SH;
	my $old_length;
	open my $fh, '+<', $fname or die "Couldn't open $fname: $!";
	binmode $fh;
	flock($fh, $lock_flags) or die "Couldn't lock $fname: $!";

	if ($has_to_read) {
		$val = do {local $/; <$fh>};
		$old_length = length $val;
        $val = decode('UTF-8', $val);
	}

	$val = $cb->($val) if $cb;

	if ($has_to_write) {
		seek $fh, 0, 0 if $has_to_read;
        my $eval = encode('UTF-8', $val);
		print $fh ($eval // '');
		my $new_length;
			$new_length = length($eval // '');
		truncate $fh, $new_length if !defined $old_length || $old_length > $new_length;
	}
	close($fh) or die "Couldn't close $fname: $!";
	return $val;
}

1;
