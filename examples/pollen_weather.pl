use strict;
use warnings;
use utf8;
use WebService::HanakoSan::CSVDownloader;
use YAML;

my $h  = WebService::HanakoSan::CSVDownloader->new( area => '03');
my $pw = $h->pollen_weather;

warn $pw;
