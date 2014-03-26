#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

use Test::More;

BEGIN {
    use_ok('Prancer');
    use_ok('Prancer::Application');
    use_ok('Prancer::Config');
    use_ok('Prancer::Const');
    use_ok('Prancer::Context');
    use_ok('Prancer::Request');
    use_ok('Prancer::Request::Upload');
    use_ok('Prancer::Response');

    use_ok('Prancer::Logger');
    use_ok('Prancer::Logger::Console');
    use_ok('Prancer::Middleware::Logger');
    use_ok('Prancer::Template');
    use_ok('Prancer::Template::TemplateToolkit');
    use_ok('Prancer::Database');
    use_ok('Prancer::Database::Driver');
    use_ok('Prancer::Database::Driver::Pg');
};

done_testing();
