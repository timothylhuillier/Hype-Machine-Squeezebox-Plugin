package Plugins::HypeM::Plugin;

# Plugin to stream audio from HypeM videos streams
#
# Released under GPLv2

use strict;


use Data::Dumper;
use vars qw(@ISA);

use URI::Escape;
use JSON::XS::VersionOneAndTwo;
use File::Spec::Functions qw(:ALL);
use List::Util qw(min max);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

use Plugins::HypeM::ProtocolHandler;

my $log;
my $compat;

BEGIN {
	$log = Slim::Utils::Log->addLogCategory({
		'category'     => 'plugin.hypem',
		'defaultLevel' => 'DEBUG',
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

$prefs->init({ password => "", username => "" });

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

  Slim::Player::ProtocolHandlers->registerHandler(
    hypem => 'Plugins::HypeM::ProtocolHandler'
  );

	Slim::Control::Request::addDispatch(['hypem', 'info'], [1, 1, 1, \&cliInfoQuery]);
}

sub shutdownPlugin {
	my $class = shift;

	# $class->saveRecentlyPlayed('now');
}

sub getDisplayName { 'PLUGIN_HYPEM' }

sub playerMenu { shift->can('nonSNApps') ? undef : 'RADIO' }

sub defaultMeta {
  my ( $client, $url ) = @_;
  
  return {
	  title => Slim::Music::Info::getCurrentTitle($url)
	};
}

sub _parseEntry {
	my $json = shift;

  my $DATA = {
	  duration => int($json->{'time'}),
	  name => $json->{'title'},
	  title => $json->{'title'},
	  artist => $json->{'artist'},
	  type => 'audio',
	  mime => 'audio/mpeg',
	  play => "hypem://" . $json->{mediaid},
	  stream_url  => $json->{'stream_pub'},
	  link => $json->{'posturl'},
	  icon => $json->{'thumb_url_large'} || "",
	  image => $json->{'thumb_url_large'} || "",
	  cover => $json->{'thumb_url_large'} || "",
  };
}

sub playlistHandler {
	my ($client, $callback, $args, $path) = @_;

	my $offset = ($args->{'index'} || 0); # ie, offset
  $log->info($offset);
	my $page = int($offset / 20) + 1;

	my $queryUrl = "http://api.hypem.com/playlist/" . $path . "/json/" . $page . "/data.js?key=f848bd68fccf9e593a2cf098616a9e43";

	$log->warn("fetching: $queryUrl");

	Slim::Networking::SimpleAsyncHTTP->new(
    sub {
	    my $http = shift;
	    $log->warn("done fetching, now parsing");

      my $menu = [];

	    my $json = eval { from_json($http->content) };

      my @skeys = keys %$json;
      my @keys;
      foreach my $k (@skeys) {
        if ($k=~/\d+/) {
          push @keys, int($k);
        }
      }

      foreach my $index (sort { $a <=> $b } @keys) {
	      my $entry = $json->{sprintf("%s", $index)};
	    	if ($index =~ /\d+/) {
          if (int($index) < $offset) {
            next;
          }
		      my $menuEntry = _parseEntry($entry);

          my $cache = Slim::Utils::Cache->new;
          $log->info("setting ". 'hypem_meta_' . $entry->{mediaid});
          $cache->set( 'hypem_meta_' . $entry->{mediaid}, _parseEntry($entry), 86400 );

		      push @$menu, $menuEntry;
		    }
	    }

      $callback->({
	      items  => $menu,
	      offset => $offset,
	      total  => scalar(@$menu),
	    });
	  }
  )->get($queryUrl);
}

sub toplevel {
	my ($client, $callback, $args) = @_;

	$callback->([
		{ 
			name => string('PLUGIN_HYPEM_POP_LASTWEEK'),
			type => 'playlist', 
		  url  => \&playlistHandler,
		  passthrough => [ "popular/lastweek" ]
		},
		{ 
			name => string('PLUGIN_HYPEM_POP_NOREMIX'),
			type => 'playlist', 
		  url  => \&playlistHandler,
		  passthrough => [ "popular/noremix" ]
		},
		{ 
			name => string('PLUGIN_HYPEM_MOST_BLOGGED_ARTISTS'),
			type => 'playlist', 
		  url  => \&playlistHandler,
		  passthrough => [ "popular/artists" ]
		},
			{ 
			name => string('PLUGIN_HYPEM_TWITTER'),
			type => 'playlist', 
		  url  => \&playlistHandler,
		  passthrough => [ "popular/twitter" ]
		},
	]);
}

	
1;
