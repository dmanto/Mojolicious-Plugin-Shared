BEGIN {
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test2::V0;
use Test::Mojo;
use Mojolicious::Lite;

$ENV{MOJO_MODE} = 'test';

plugin 'Shared';

my $c = Test::Mojo->new->app->build_controller;
is $c->shared(my_hash => 'something'), 'something', 'writes';
is $c->shared('my_hash'), 'something', 'reads';
is $c->shared(my_hash => sub {uc shift}), 'SOMETHING', 'modifies';
is $c->shared('my_hash'), 'SOMETHING', 'reads modified';
is $c->shared(my_counter => ''), '', 'resets counter';
is $c->shared(my_counter => sub {++$_}), 1, 'increments counter';
is $c->shared(my_counter => sub {++$_}), 2, 'increments counter twice';
done_testing;
