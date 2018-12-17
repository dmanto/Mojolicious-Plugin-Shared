use Mojo::Base -strict;
use Time::HiRes qw/time sleep/;
use Data::Dumper;
use Fcntl qw/:flock SEEK_END/;
use FindBin;

use lib "$FindBin::Bin/../lib";
use Mojolicious::Lite;
plugin 'Shared';
app->start;

my @kids;
$SIG{INT} = sub { die "$$ dying\n" };


sub inc_key {
	my ($k) = @_;
	app->shared("PID:$k" => sub {++$_});
}

for (1 .. 50) {
	my $child;
	unless ($child = fork) {        # i'm the child
		die "cannot fork: $!" unless defined $child;
		count();
		exit;
	}
	app->shared("PID:$child" => 0);
	push @kids, $child;
}

my $original_time = time;
while (1) {
	sleep 1;
	my $sum = 0;
	for my $pid (@kids) {
		my $val = app->shared("PID:$pid");
		$sum += $val;
	}
	my $dt = time - $original_time;
	say sprintf '%.1f segs, promedio es %.3f',$dt, $sum/$dt;
}
die "Child $$ shouldn't have reached this";


sub count {
	while (1) {
		inc_key($$);
	}
}
