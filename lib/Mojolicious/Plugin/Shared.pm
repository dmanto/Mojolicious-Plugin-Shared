package Mojolicious::Plugin::Shared;
use Mojo::Base 'Mojolicious::Plugin';
use File::Spec;
use Fcntl ':flock';
use Mojo::Util qw/b64_encode b64_decode md5_sum/;
use Mojo::File 'path';
use Carp 'croak';

# use Sereal qw(sereal_encode_with_object sereal_decode_with_object);
our $VERSION = "0.01";
use Data::Dumper;
use constant SHARED_DIR => 'mojo_shared_';
my $shareddir;
my %file_paths;
my $semaphore_file; #just to create a file

# my $enc = Sereal::Encoder->new;
# my $dec = Sereal::Decoder->new;


sub register {
	my ($self, $app) = @_;

	# for *nix systems, getpwuid takes precedence
	# for win systems or wherever getpwuid is not implemented,
	# eval returns undef so getlogin takes precedence
	$shareddir = path($app->config->{shared}{dir} // File::Spec->tmpdir)->child(SHARED_DIR . (eval { scalar getpwuid($<) } || getlogin || 'nobody'),$app->mode);
	$shareddir->make_path unless -d $shareddir;
	$semaphore_file = $shareddir->child('semaphore.lock')->to_string;
	$app->helper(shared => \&_shared);
}


sub _shared {
	my ($c, $key, $arg) = @_;
	my ($cb, $val, $has_to_read, $has_to_write);
	if (ref $arg eq 'CODE') {
		$cb = $arg;
		$has_to_read = $has_to_write = 1;
	} elsif (defined $arg) {
		$val = $arg;
		$has_to_write = 1;
	} else {
		$has_to_read = 1;
	}
	unless ($file_paths{$key}) {
		my $token = substr md5_sum($key), 4;
		my ($tkn1, $tkn2) = $token  =~ m/../g;
		my $dir = $shareddir->child($tkn1)->child($tkn2);
		my $file = $dir->child($token);
		open(my $sf, '>', $semaphore_file) or die "Couldn't open $semaphore_file for write: $!";
		flock($sf, LOCK_EX) or die "Couldn't lock $semaphore_file: $!";
		$dir->make_path unless -d $dir;
		$file->touch unless -f $file;
		close($sf) or die "Couldn't close $semaphore_file: $!";
		$file_paths{$key} = $file->to_string;
	}

	# only case for shared locking: key only arg
	my $fname = $file_paths{$key};
	my $lock_flags = $has_to_write ? LOCK_EX : LOCK_SH;
	my $old_length;
	open my $fh, '+<', $fname or die "Couldn't open $fname: $!";
	binmode $fh;
	flock($fh, $lock_flags) or die "Couldn't lock $fname: $!";

	if ($has_to_read) {

		# got the lock, slurp file here
		$val = do {local $/; <$fh>};
		$old_length = length $val;

		# @sh_val = @{sereal_decode_with_object($dec, $inp)->{$key}} if $old_length;
	}

	# say STDERR "key $key, ANTES: " ,$sh_val[0];
	$val = $cb->($val) if $cb;

	# say STDERR "key $key, DESPUES: " ,$sh_val[0];
	if ($has_to_write) {
		seek $fh, 0, 0 if $has_to_read;
		# truncate $fh, 0;

		# my $out = sereal_encode_with_object($enc, {$key => \@sh_val});
		print $fh $val;
		my $new_length = length $val;

		# say STDERR Dumper \@sh_val;

		truncate $fh, $new_length if defined $old_length && $old_length > $new_length;
	}
	close $fh or die "Couldn't close $fname: $!";
	return $val;
}


1;
__END__

=encoding utf8
 
=head1 NAME
 
Mojolicious::Plugin::Shared is a highly portable file / directory based Shared Memory helper for Mojolicious and Mojolicious::Lite projects
 
=head1 SYNOPSIS
 
  # Initialize a shared var
 
  # Mojolicious::Lite
 
  plugin 'Shared';
  app->shared(counter => sub {0});
  get '/' => sub {
      my $c = shift;
      my $counter = $c->shared(counter => sub {++$_->[0]});
      $c->render(text => "Hello World, this is visit # $counter");
  }
  # Mojolicious
 
  $self->plugin('Shared');
 
# More than one schedule, or more options requires extended syntax
 
  plugin Cron => (
  sched1 => {
    base    => 'utc', # not needed for local time
    crontab => '*/10 15 * * *', # every 10 minutes starting at minute 15, every hour
    code    => sub {
      # job 1 here
    }
  },
  sched2 => {
    crontab => '*/15 15 * * *', # every 15 minutes starting at minute 15, every hour
    code    => sub {
      # job 2 here
    }
  });
 
=head1 DESCRIPTION
 
L<Mojolicious::Plugin::Cron> is a L<Mojolicious> plugin that allows to schedule tasks
 directly from inside a Mojolicious application.
 
You should not consider it as a *nix cron replacement, but as a method to make a proof of
concept of a project. It helps also in the deployment phase because in the end it
could mean less and simpler installation/removing tasks.
 
As an extension to regular cron, seconds are supported in the form of a sixth space
separated field (For more information on cron syntax please see L<Algorithm::Cron>).
 
=head1 BASICS
 
When using preforked servers (as applications running with hypnotoad), some coordination
is needed so jobs are not executed several times.
 
L<Mojolicious::Plugin::Cron> uses standard Fcntl functions for that coordination, to assure
a platform-independent behavior.
 
Please take a look in the examples section, for a simple Mojo Application that you can
run on hypnotoad, try hot restarts, adding / removing workers, etc, and
check that scheduled jobs execute without interruptions or duplications.
 
=head1 EXTENDEND SYNTAX HASH
 
When using extended syntax, you can define more than one crontab line, and have access
to more options
 
  plugin Cron => {key1 => {crontab line 1}, key2 => {crontab line 2}, ...};
 
=head2 Keys
 
Keys are the names that identify each crontab line. They are used to form a locking 
semaphore file to avoid multiple processes starting the same job. 
 
You can use the same name in different Mojolicious applications that will run
at the same time. This will ensure that not more that one instance of the cron job
will take place at a specific scheduled time. 
 
=head2 Crontab lines
 
Each crontab line consists of a hash with the following keys:
 
=over 8
  
=item base => STRING
  
Gives the time base used for scheduling. Either C<utc> or C<local> (default C<local>).
  
=item crontab => STRING
  
Gives the crontab schedule in 5 or 6 space-separated fields.
  
=item sec => STRING, min => STRING, ... mon => STRING
  
Optional. Gives the schedule in a set of individual fields, if the C<crontab>
field is not specified.
 
For more information on base, crontab and other time related keys,
 please refer to L<Algorithm::Cron> Contstructor Attributes. 
 
=item code => sub {...}
 
Mandatory. Is the code that will be executed whenever the crontab rule fires.
Note that this code *MUST* be non-blocking.
 
=back
 
=head1 METHODS
 
L<Mojolicious::Plugin::Cron> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.
 
=head2 register
 
  $plugin->register(Mojolicious->new, {Cron => '* * * * *' => sub {}});
 
Register plugin in L<Mojolicious> application.
 
=head1 WINDOWS INSTALLATION
 
To install in windows environments, you need to force-install module
Test::Mock::Time, or installation tests will fail.
 
=head1 AUTHOR
 
Daniel Mantovani, C<dmanto@cpan.org>
 
=head1 LICENSE

Copyright (C) Daniel Mantovani.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Daniel Mantovani E<lt>daniel@gmail.comE<gt>

=cut


