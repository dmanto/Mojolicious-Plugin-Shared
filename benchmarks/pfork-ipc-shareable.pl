use Mojo::Base -strict;
use Time::HiRes qw/time sleep/;

use IPC::Shareable;
use Data::Dumper;

my @kids;
my $handle = tie my @buffer, 'IPC::Shareable', undef, { destroy => 1 };
$SIG{INT} = sub { die "$$ dying\n" };

for (1 .. 10) {
	my $child;
	unless ($child = fork) {        # i'm the child
		die "cannot fork: $!" unless defined $child;
		squabble();
		exit;
	}
	push @kids, $child;  # in case we care about their pids
}

my $i = 1;
while (1) {
	my $sum = 0;
	sleep 1;
	$handle->shlock();
	$sum+=$_ for @buffer;
	$handle->shunlock();
	say sprintf '%d promedio es %.3f',$i, $sum/$i;
	$i++;
}
die "Not reached";


sub squabble {
	while (1) {
		$handle->shlock();
		$buffer[$$ % 10]++;
		$handle->shunlock();

		# sleep 0.01;
	}
}
