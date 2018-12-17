use strict;
use warnings;
use Test::More tests => 1;

BEGIN {
    use_ok('Mojolicious::Plugin::Shared');
}

diag("Testing M::P::Shared $Mojolicious::Plugin::Shared::VERSION");