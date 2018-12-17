use Mojo::Base -strict;
use Time::HiRes qw/time sleep/;
use Data::Dumper;
use DBI;

my @kids;
my $dbfile = './mydb.db';
$SIG{INT} = sub { die "$$ dying\n" };

my $master_dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "");
$master_dbh->do(
	q{
    CREATE TABLE IF NOT EXISTS cuentas (pid INTEGER PRIMARY KEY, n INTEGER);
    DELETE from cuentas;
}
) or die $master_dbh->errstr;

for (1 .. 10) {
	my $child;
	unless ($child = fork) {        # i'm the child
		die "cannot fork: $!" unless defined $child;
		squabble();
		exit;
	}
	push @kids, $child;  # in case we care about their pids
}

my $original_time = time;
my $sth = $master_dbh->prepare(
	q{
    SELECT n FROM cuentas WHERE pid=?
}
) or die $master_dbh->errstr;
while (1) {
	my $sum = 0;
	sleep 1;
	for my $pid (@kids) {
		$sth->execute($pid);
		my @row = $sth->fetchrow_array;
		$sum += $row[0] // 0;
	}
	my $dt = time - $original_time;
	say sprintf '%.1f segs, promedio es %.3f',$dt, $sum/$dt;
}
die "Not reached";


sub squabble {
	my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "");
	$dbh->do(
		qq{
        INSERT INTO cuentas(pid, n) VALUES(?,?)
    }, undef, $$, 0
	) or die $dbh->errstr;
	while (1) {
		$dbh->do(
			qq{
        UPDATE cuentas SET n = n + 1 WHERE pid=?;
    }, undef, $$
		) or die $dbh->errstr;

		# sleep 0.01;
	}
}
