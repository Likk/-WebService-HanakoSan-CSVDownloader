package WebService::HanakoSan::CSVDownloader;

=encoding utf8

=head1 NAME

  WebService::HanakoSan::CSVDownloader - Web scraping client for perl at kafun.taiki.go.jp.

=head1 SYNOPSIS

  use WebService::HanakoSan::CSVDownloader;
  my $h              = WebService::HanakoSan::CSVDownloader->new();
  my $pollen_weather = $h->pollen_weather();

=head1 DESCRIPTION

  WebService::HanakoSan::CSVDownloader is scraping library client for perl at  kafun.taiki.go.jp.

=cut

use strict;
use warnings;
use utf8;
use Carp;
use Encode;
use Furl;
use HTTP::Request::Common qw/POST GET/;
use Web::Scraper;

our $VERSION = '1.00';

=head1 CONSTRUCTOR AND STARTUP

=head2 new

  Creates and returns a new kafun.taiki.go.jp object.

=cut

sub new {
    my $class = shift;
    my %args = @_;

    my $self = bless { %args }, $class;

    $self->{last_req} ||= time;
    $self->{interval} ||= 1;

    $self->ua();

    return $self;
}

=head1 Accessor

=over

=item B<ua>

  Furl object.

=cut

sub ua {
    my $self = shift;
    my $ua   = shift;
    return $self->{ua} ||= do {
        my $mech = Furl->new(
            agent      => 'Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.89 Safari/537.36',
            timeout    => 600,
        );
    }
}

=item B<interval>

  http request interval.

=item B<last_request_time>

  request time at last request.

=item B<last_content>

  cache at last decoded content.

=cut

sub interval          { return shift->{interval} ||= 1    }

sub last_request_time { return shift->{last_req} ||= time }

sub last_content {
    my $self = shift;
    my $arg  = shift // '';

    $self->{last_content} = $arg if $arg;

    return $self->{last_content} || '';
}

=item B<base_url>

=cut

sub base_url {
    my $self = shift;
    my $arg  = shift || '';

    if($arg){
        $self->{base_url} = $arg;
        $self->{conf}     = undef;
    }
    return $self->{base_url} ||= 'http://kafun.taiki.go.jp/';
}

=back

=head1 METHODS

=head2 conf

  url path config

=cut

sub conf {
    my $self = shift;
    return $self->{conf} ||= do {
        my $base_url =  $self->base_url();
        my $conf = {
            top      => $base_url,
            download => sprintf("%s/DownLoad1.aspx", $base_url),
        };
        $conf;
    };
}

=head2 asp_eval

  cache ASP.NET WebForm Value
    - __VIEWSTATE
    - __VIEWSTATEGENERATOR
    - __EVENTVALIDATION

=cut

sub asp_eval {
    my ($self, $arg) = @_;
    $self->{asp_eval} = $arg if $arg;
    return $self->{asp_eval};
}

sub pollen_weather {
    my $self     = shift;
    my $area     = '03'; #FIXME 03 area
    my $mst_code = $self->{mst_code} || '51310200';
    my $res;

    my $mstlist  = {};
    my $term     = {};

    my $header  = [
        'Connection'      => 'keep-alive',
        'Content-Type'    => 'application/x-www-form-urlencoded',
        'Host'            => 'kafun.taiki.go.jp',
        'Origin'          => 'http://kafun.taiki.go.jp',
        'User-Agent'      => $self->ua->agent,
    ];

    {
        my $res       = $self->_get($self->conf->{download}, $header);
        my $form_data = $self->parse_download_form($self->last_content);
        $self->asp_eval($form_data->{asp_eval});
        $mstlist = { map { $_         => 'on'           } @{ $form_data->{checkbox}->{mstlist}} };
        $term    = { map { $_->{name} => $_->{selected} } @{ $form_data->{default_term} }       };
    }

    {
        my $asp_eval = $self->asp_eval();
        my $content = +{
            '__EVENTTARGET'      => '',
            '__LASTFOCUS'        =>  '',
            __VIEWSTATE          => $asp_eval->{viewstate},
            __EVENTVALIDATION    => $asp_eval->{eventvalidation},
            __VIEWSTATEGENERATOR => $asp_eval->{viewstategenerator},
            ddlArea              => $area,
            download             => 'ダウンロード',
            %$mstlist,
            %$term,
        };
        $res = $self->_post($self->conf->{download}, $header, $content);
        Encode::from_to($res, 'cp932', 'utf8');
        $res =~ s/\r\n/\n/g;
    };
    $res = join("\n", grep { $_ =~ m{$mst_code} } split(/\n/, $res));
    return $res;
}

sub parse_download_form {
    my ($self, $html) = @_;
    my $scraper = scraper  {
        process '//form[@id="Form1"]', 'asp_eval' => scraper {
            process '//input[@id="__VIEWSTATE"]',          viewstate          =>  '@value';
            process '//input[@id="__VIEWSTATEGENERATOR"]', viewstategenerator =>  '@value';
            process '//input[@id="__EVENTVALIDATION"]',    eventvalidation    =>  '@value';
        };
        process '//table[@id="CheckBoxMstList"]', checkbox => scraper {
            process '//input[@type="checkbox"]', 'mstlist[]' => '@name';
        };
        process '//select', 'default_term[]' => scraper {
            process '*',                              name     => '@name';
            process '//option[@selected="selected"]', selected => '@value';
        };
        result qw/asp_eval checkbox default_term/;
    };
    return $scraper->scrape($html);
}

=head1 PRIVATE METHODS.

=over

=item B<_parse>

=cut

sub _parse {
    my $self = shift;
}

=item B<_sleep_interval>

  interval for http accessing.

=cut

sub _sleep_interval {
    my $self = shift;
    my $wait = $self->interval - (time - $self->last_request_time);
    sleep $wait if $wait > 0;
    $self->_set_last_request_time();
}

=item B<_set_last_request_time>

  set request time

=cut

sub _set_last_request_time { shift->{last_req} = time }

=item B<_post>

  furl post with interval.

=cut

sub _post {
    my ($self, $url, $header, $content) = @_;
    $self->_sleep_interval;
    my $request = HTTP::Request::Common::POST(
        $url,
        @$header,
        Content => [ %$content ]
    );
    my $res     = $self->ua->request($request);
    return $self->_content($res);
}

=item B<_get>

  furl get with interval.

=cut

sub _get {
    my ($self, $url, $header, $content) = @_;
    $self->_sleep_interval;
    my $request = GET($url, $header);
    my $res     = $self->ua->request($request);
    return $self->_content($res);
}


=item b<_content>

  decode content from furl request.

=cut

sub _content {
    my ($self, $res, $encoding)  = @_;
    my $content = $res->decoded_content();
    return $self->last_content($content);
}

=back

=cut

=head1 AUTHOR

  likkradyus E<lt>perl {at} li.que.jpE<gt>

=head1 SEE ALSO

  L<WWW::Mechanize>,
  L<http://kafun.taiki.go.jp/>,

=head1 LICENSE

  This library is free software; you can redistribute it and/or modify
  it under the same terms as Perl itself.

=cut

1;
