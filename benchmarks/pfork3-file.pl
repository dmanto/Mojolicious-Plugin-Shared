use Mojo::Base -strict;
use Time::HiRes qw/time sleep/;
use Data::Dumper;
use Fcntl qw/:flock SEEK_END/;
use FindBin;

my @kids;
my $dbfile = "$FindBin::Bin/myfile.db";
$SIG{INT} = sub { die "$$ dying\n" };

sub inc_key {
	my ($k) = @_;
	if (open my $fh, '+<', $dbfile) {
		flock($fh, LOCK_EX) or die "Cannot lock $dbfile - $!\n";
		my %h = split /:/, <$fh> // '';
		$h{$k}++;
		seek $fh, 0, 0;
		# truncate $fh, 0;
		print $fh join(':', %h);
		close $fh;
	}
}


sub get_hash {
	if (open my $fh, '+<', $dbfile) {
		flock($fh, LOCK_SH) or die "Cannot lock $dbfile - $!\n";
		my %h = split /:/, <$fh> // '';
		close $fh;
		return %h;
	}
}

open (my $aux, '>', $dbfile) or die "Cannot create $dbfile - $!" ;
close $aux or die "Cannot close $dbfile - $!";

for (1 .. 50) {
	my $child;
	unless ($child = fork) {        # i'm the child
		die "cannot fork: $!" unless defined $child;
		count();
		exit;
	}
	push @kids, $child;
}

my $original_time = time;
while (1) {
	sleep 1;
	my $sum = 0;
	my %h = get_hash;
	for my $pid (@kids) {
		$sum += $h{$pid} // 0;
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
