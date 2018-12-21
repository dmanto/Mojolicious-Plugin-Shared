BEGIN {
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}
use utf8;
use Test2::V0;
use Mojo::Iutils;

$ENV{MOJO_MODE} = 'test';


my $c = Mojo::Iutils->new;
is $c->istash(my_string => 'something'), 'something', 'writes';
is $c->istash('my_string'), 'something', 'reads';
is $c->istash(my_string => sub {uc shift}), 'SOMETHING', 'modifies';
is $c->istash('my_string'), 'SOMETHING', 'reads modified';
is $c->istash(my_string => 'smth'), 'smth', 'shorter';
is $c->istash('my_string'), 'smth', 'reads shorter';
is $c->istash(my_string => 'Mojo 8.0 (🦹)'), 'Mojo 8.0 (🦹)', 'writes utf-8';
is $c->istash('my_string'), 'Mojo 8.0 (🦹)', 'reads utf-8';
is $c->istash(my_string => undef), undef, 'deletes';
is $c->istash('my_string'), '', 'reads deleted';
is $c->istash(my_counter => ''), '', 'resets counter';
is $c->istash(my_counter => sub {++$_}), 1, 'increments counter';
is $c->istash(my_counter => sub {++$_}), 2, 'increments counter twice';
done_testing;
