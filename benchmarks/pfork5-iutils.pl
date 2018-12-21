use Mojo::Base -strict;
use Time::HiRes qw/time sleep/;
use Data::Dumper;
use Fcntl qw/:flock SEEK_END/;
use FindBin;

use lib "$FindBin::Bin/../lib";
use Mojo::Iutils;

my $shrd = Mojo::Iutils->new;

my @kids;
$SIG{INT} = sub { die "$$ dying\n" };


sub inc_key {
	my ($k) = @_;
	$shrd->istash("PID-$k" => sub {++$_});
}

for (1 .. 50) {
	my $child;
	unless ($child = fork) {        # i'm the child
		die "cannot fork: $!" unless defined $child;
		count();
		exit;
	}
	$shrd->istash("PID-$child" => 0);
	push @kids, $child;
}

my $original_time = time;
while (1) {
	sleep 1;
	my $sum = 0;
	for my $pid (@kids) {
		my $val = $shrd->istash("PID-$pid");
		$sum += $val;
	}
	my $dt = time - $original_time;
	say sprintf '%.1f segs, promedio es %.3f',$dt, $sum/$dt;
}
die "Child $$ shouldn't have reached this";


sub count {
	while (1) {
        sleep 0.001;
		inc_key($$);
	}
}
