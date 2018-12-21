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
our $FTIME; # Fake time, for testing only
my ($varsdir, $queuesdir, $pubsubsdir, $semaphore_file);
my $valid_fname = qr/^[\w\.-]+$/;
my %catched;


sub get_path {
	my ($self, $key) = @_;
	die "Key $key not valid" unless $key =~ $valid_fname;
	unless ($varsdir) { # inicializes $varsdir & $semaphore_file
		$varsdir = path($self->base_dir, VARS_DIR );
		$varsdir->make_path unless -d $varsdir;
		$semaphore_file = $varsdir->sibling('semaphore.lock')->to_string;
	}
	return $varsdir->child($key)->to_string;
}


sub ikeys {
	my $self = shift;
	$self->get_path('dummy') unless $varsdir; # initializes $varsdir
	return $varsdir->list->map('basename')->to_array;
}


sub gc {
	my $self = shift;
	$self->istash($_) for @{$self->ikeys};
	my $ctime = sprintf '%10d', $FTIME // time; # current time, 10 digits number
	for my $key (keys %catched) {
		delete $catched{$key} unless $ctime <= $catched{$key}{tstamp} + CATCH_VALID_TO;
	}
	return $self;
}


sub istash {
	my ($self, $key, $arg, %opts) = @_;
	my ($cb, $val, $set_val, $last_def, $expires_by, $type);
	my $ctime = sprintf '%10d', $FTIME // time; # current time, 10 digits number
	$cb = $arg if ref $arg eq 'CODE';
	my $has_to_write = @_ % 2; # odd nmbr of arguments --> write
	$set_val = $arg unless $cb or !$has_to_write;

	unless (exists $catched{$key} && $ctime <= $catched{$key}{tstamp} + CATCH_VALID_TO) {
		my $file = $self->get_path($key);
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
	my $slurped_file = do {local $/; <$fh>};
	$old_length = length $slurped_file;
	($last_def, $expires_by, $type, $val) = unpack('a10a10a1a*', $slurped_file);

	if ($last_def && $expires_by && $expires_by gt $ctime) {
		$val = decode('UTF-8', $val) if $type && $type eq 1;
	} else {
		undef $val;
	}
	if ($has_to_write) {
		$val = $cb ? $cb->($val) : $set_val;

		my $to_print;
		my $expires_set = sprintf '%10d', $opts{expire} // 9999999999;
		undef $val if $ctime >= $expires_set;
		if (defined $val) {
			$catched{$key}{tstamp} = $last_def = $ctime;
			my $enc_val;
			if (utf8::is_utf8($val)) {$type=1;$enc_val = encode 'UTF-8', $val}
			else {$type = 0; $enc_val = $val}
			$to_print = pack 'a10a10a1a*', $last_def, $expires_set, $type, $enc_val;
		} else {
			$to_print = $last_def // '';
		}

		seek $fh, 0, 0;
		print $fh ($to_print);
		my $new_length = length($to_print);
		truncate $fh, $new_length if !defined $old_length || $old_length > $new_length;
	}

	close($fh) or die "Couldn't close $fname: $!";
	$last_def ||= 0;
	$catched{$key}{tstamp} = $last_def;
	unless (defined $val || $ctime <= $last_def + CATCH_VALID_TO + CATCH_SAFE_WINDOW) {
		open(my $sf, '>', $semaphore_file) or die "Couldn't open $semaphore_file for write: $!";
		flock($sf, LOCK_EX) or die "Couldn't lock $semaphore_file: $!";
		unlink $fname if -f $fname;
		close($sf) or die "Couldn't close $semaphore_file: $!";
	}
	return $val;
}

1;
