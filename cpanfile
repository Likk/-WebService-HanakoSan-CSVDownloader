requires 'perl', '5.018004';

requires 'Furl';
requires 'HTTP::Request::Common';
requires 'Web::Scraper';

on 'test' => sub {
    requires 'Test::More';
};
