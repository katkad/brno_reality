#!/usr/bin/env perl

use strict;
use warnings;

use Database::DumpTruck;
use Encode qw(decode_utf8 encode_utf8);
use HTML::TreeBuilder;
use LWP::UserAgent;
use English; #OUTPUT_AUTOFLUSH

# Don't buffer.
$OUTPUT_AUTOFLUSH = 1;

binmode STDOUT, ":encoding(UTF-8)";

my $base_url = 'https://www.bezrealitky.cz';
my $long_url = $base_url . '/vypis/nabidka-prodej/byt/jihomoravsky-kraj/okres-brno-mesto?ownership%5B0%5D=osobni&construction%5B0%5D=cihla';

my $dt = Database::DumpTruck->new({
	'dbname' => 'data.sqlite',
	'table' => 'data',
});

my $ua = LWP::UserAgent->new(timeout => 10);
$ua->env_proxy;

# datum bude posledny den kedy bol inzerat este zverejneny
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
$year += 1900;
# $mon the month in the range 0..11
$mon++;
my $date =  "$year/$mon/$mday";
 
my $table;

sub scrape_page($) {
	my ($url) = @_;
	print 'Page: ' . $url . "\n";
	my $response = $ua->get($url);
	 
	my $data;
	if ($response->is_success) {
	    $data = $response->decoded_content;
	}
	else {
	    die $response->status_line;
	}

	my $root = HTML::TreeBuilder->new;
	$root->parse($data);
	$root->elementify;

	$table = $root->look_down('class' => 'b-filter__inner pb-40');

	my @tr = $table->look_down('class' => 'mb-20');

	foreach my $tr (@tr) {
		my $popis = $tr->look_down('class' =>  'product__info-text')->as_text;
		my $text = $tr->look_down('class', 'product__link js-product-link')->as_text;
		print $text . "\n";

		my ($ulice, $cast);
		if (encode_utf8($text) =~ /^\s?Staré Brno/) {
			$cast = decode_utf8('Staré Brno');
		} elsif ($text =~ /Brno - /) {
			($ulice, $cast) = $text =~ /^(.+)?,? ?Brno - ([\S ]+), Jihom/;
		} else {
			($ulice, $cast) = $text =~ /(.+), (.+),/;
		};

		if ($ulice) {
			$ulice =~ s/, //;
			$ulice =~ s/^ //;
		} else {
			$ulice = '';
		};

		print $ulice . ' ' . $cast . "\n";

		my $link = $base_url . $tr->look_down('class', 'product__link js-product-link')->attr_get_i('href');
		my $product_note = $tr->look_down('class' =>  'product__note')->as_text;
		my ($dispozice, $velikost) = $product_note =~ /Prodej bytu (\S+), (\d+) /;
		my $product_value = $tr->look_down('class' =>  'product__value')->as_text;
		my ($cena) = $product_value =~ /([\d\.]+) K/;
		$cena =~ s/\.//g;

		print "\n";

		$dt->upsert({
			'Popis' => $popis,
			'Ulice' => $ulice,
			'Lokalita' => $cast,
			'Url' => $link,
			'Dispozice' => $dispozice,
			'Rozloha' => $velikost,
			'Cena' => $cena,
			'Zdroj' => 'bezrealitky',
			'Datum' => $date,
			'Za_metr' => sprintf('%.2f', $cena / $velikost),
		});
	}
};

scrape_page($long_url);

$dt->create_index(['Url'], undef, 'IF NOT EXISTS', 'UNIQUE');

my @tr = $table->look_down('class' => 'page-link pagination__page');
my $cur_page = 1;
my $max_page = 1;
foreach my $tr (@tr) {
	my $page = encode_utf8($tr->as_text);
	if ($page !~ /\d+/) {
		next;
	} else {
		$max_page = $page;
	};
};

for (++$cur_page; $cur_page <= $max_page; $cur_page++) {
	scrape_page($long_url . '&page=' . $cur_page);
};
