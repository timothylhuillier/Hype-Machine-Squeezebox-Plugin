package Plugins::HypeM::Plugin;

# Plugin to stream audio from HypeM videos streams
#
# Released under GPLv2

use strict;

use vars qw(@ISA);

use URI::Escape;
use JSON::XS::VersionOneAndTwo;
use File::Spec::Functions qw(:ALL);
use List::Util qw(min max);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $log;
my $compat;

my %METADATA_CACHE= {};

BEGIN {
	$log = Slim::Utils::Log->addLogCategory({
		'category'     => 'plugin.hypem',
		'defaultLevel' => 'WARN',
		'description'  => string('PLUGIN_HYPEM'),
	}); 

	# Always use OneBrowser version of XMLBrowser by using server or packaged version included with plugin
	if (exists &Slim::Control::XMLBrowser::findAction) {
		$log->info("using server XMLBrowser");
		require Slim::Plugin::OPMLBased;
		push @ISA, 'Slim::Plugin::OPMLBased';
	} else {
		$log->info("using packaged XMLBrowser: Slim76Compat");
		require Slim76Compat::Plugin::OPMLBased;
		push @ISA, 'Slim76Compat::Plugin::OPMLBased';
		$compat = 1;
	}
}

my $prefs = preferences('plugin.hypem');

$prefs->init({ prefer_lowbitrate => 0, recent => [] });

tie my %recentlyPlayed, 'Tie::Cache::LRU', 20;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed   => \&toplevel,
		tag    => 'hypem',
		menu   => 'radios',
		is_app => $class->can('nonSNApps') ? 1 : undef,
		weight => 10,
	);

	if (!$::noweb) {
		require Plugins::HypeM::Settings;
		Plugins::HypeM::Settings->new;
	}

	for my $recent (reverse @{$prefs->get('recent')}) {
		$recentlyPlayed{ $recent->{'url'} } = $recent;
	}

  Slim::Formats::RemoteMetadata->registerProvider(
    match => qr/hypem.com/,
    func => \&metadata_provider,
  );

	Slim::Control::Request::addDispatch(['hypem', 'info'], [1, 1, 1, \&cliInfoQuery]);
}

sub shutdownPlugin {
	my $class = shift;

	$class->saveRecentlyPlayed('now');
}

sub getDisplayName { 'PLUGIN_HYPEM' }

sub playerMenu { shift->can('nonSNApps') ? undef : 'RADIO' }

sub defaultMeta {
  my ( $client, $url ) = @_;
  
  return {
	  title => Slim::Music::Info::getCurrentTitle($url)
	};
}


# TODO: make this async
sub metadata_provider {
  my ($client, $url) = @_;
  if (exists $METADATA_CACHE{$url}) {
    return $METADATA_CACHE{$url};
  }
  return defaultMeta( $client, $url );
}

sub _parseEntry {
	my $json = shift;

  my $DATA = {
	  #duration => $json->{'duration'} / 1000,
	  name => $json->{'title'},
	  title => $json->{'title'},
	  artist => $json->{'artist'},
	  type => 'audio',
	  mime => 'audio/mpeg',
	  play => $json->{'stream_url_raw'},
	  #url  => $json->{'permalink_url'},
	  link => $json->{'posturl'},
	  icon => $json->{'thumb_url_large'} || "",
	  image => $json->{'thumb_url_large'} || "",
	  cover => $json->{'thumb_url_large'} || "",
  };
}

sub playlistHandler {
	my ($client, $callback, $args, $path) = @_;

	my $index = ($args->{'index'} || 0); # ie, offset
	my $page = $index / 20;

	my $queryUrl = "http://api.hypem.com/playlist/" . $path . "/json/" . $page . "/data.js?key=f848bd68fccf9e593a2cf098616a9e43";

	$log->warn("fetching: $queryUrl");

# 0: {
# mediaid: "1j46f",
# artist: "Charli XCX",
# title: ""Valentine"",
# dateposted: 1330084587,
# siteid: 1288,
# sitename: "Faded Glamour",
# posturl: "http://www.fadedglamour.co.uk/2012/02/ones-to-watch-tips-2012-charli-xcx.html",
# postid: 1729896,
# dateposted_first: 1329359575,
# siteid_first: 15146,
# sitename_first: "AwkwardSound",
# posturl_first: "http://www.awkwardsound.com/2012/02/charli-xcx.html",
# postid_first: 1721694,
# loved_count: 105,
# posted_count: 3,
# stream_url: "http://api.hypem.com/serve/f/509/1j46f/6432e138cdcc7b07ef95e05b5e67e795.mp3",
# stream_pub: "http://hypem.com/serve/public/1j46f",
# stream_url_raw: "http://t01a.hypem.com/sec/75fbb829963a73d9ef0435d29a4ac746/4f4959e0/archive/509/17/19502.mp3",
# stream_url_raw_low: "http://t01a.hypem.com/sec/703e6da7b1b56a89c3a5454f27ace5c9/4f4959e0/squeeze.pl?arg=9&file=17/19502.mp3",
# stream_url_raw_sample: "http://t01a.hypem.com/sec/83170e90307077c3f789ccda3223d7fa/4f4959e0/sample.pl?arg=9&file=17/19502.mp3",
# thumb_url: "http://static-ak.hypem.net/images/albumart4.gif",
# thumb_url_large: "http://static-ak.hypem.net/images/blog_images/1288.jpg",
# time: 270,
# description: "Words: Saam Das (unless otherwise stated)  Part two of our bands to watch for the next ten months or so. Or longer? Part three to follow shortly. Part one comprised of Alabama Shakes, Alt-J, and BASTILLE - tipped by Emily Solan, Jack Thomson and myself re",
# itunes_link: "http://hypem.com/go/itunes_search/Charli%20XCX"
# },
use Data::Dumper;

	Slim::Networking::SimpleAsyncHTTP->new(
    sub {
	    my $http = shift;
	    $log->warn("done fetching, now parsing");

      my $menu = [];

	    my $json = eval { from_json($http->content) };
	    while ( my ($index, $entry) = each(%$json) ) {
	    	if ($index =~ /\d+/) {
		      $log->warn(Dumper($entry));
		      $log->warn(Dumper(_parseEntry($entry)));

		      my $menuEntry = _parseEntry($entry);
		      $METADATA_CACHE{$menuEntry->{'play'}} = _parseEntry($entry);

		      push @$menu, $menuEntry;
		    }
	    }

      $callback->({
	      items  => $menu,
	      offset => $index,
	      total  => 50,
	    });
	  }
  )->get($queryUrl);
}

sub toplevel {
	my ($client, $callback, $args) = @_;

	$callback->([
		{ 
			playall => 1,
			name => string('PLUGIN_HYPEM_POP_NOREMIX'),
			type => 'playlist', 
		  url  => \&playlistHandler,
		  passthrough => [ "popular/noremix" ]
		}
	]);
}

	
1;
