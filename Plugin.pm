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

use Plugins::HypeM::ProtocolHandler;

my $log;
my $compat;

my %METADATA_CACHE= {};

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


# TODO: make this async
sub metadata_provider {
  my ($client, $url) = @_;
  $log->error($url);
  if (exists $METADATA_CACHE{$url}) {
    return $METADATA_CACHE{$url};
  } elsif ($url =~ /\/([^\/]+)\/[^\/]+.mp3$/) {
  	$log->error($1);
    Slim::Utils::Timers::killTimers( $client, \&fetchMetadata );
    $client->master->pluginData( webapifetchingMeta => 1 );

    fetchMetadata( $client, $url, $1 );
	  # http://api.hypem.com/serve/f/509/zh3k/4308df2718040bc81992e9cdb60102f1.mp3",
	  # http://api.hypem.com/playlist/item/zh3k/json/1/data.js
	}
  return defaultMeta( $client, $url );
}

sub _gotMetadata {
	my $http      = shift;
	my $client    = $http->params('client');
	my $url       = $http->params('url');
	my $content   = $http->content;


  if ( $@ ) {
	  $http->error( $@ );
	  _gotMetadataError( $http );
	  return;
  }
  
  my $json = eval { from_json($content) };

  $client->master->pluginData( webapifetchingMeta => 0 );

  my $DATA = _parseEntry($json->{'0'});
  my $cache = Slim::Utils::Cache->new;
  $log->info("setting ". 'hypem_meta_' . $json->{mediaid});
  $cache->set( 'hypem_meta_' . $json->{mediaid}, $DATA, 86400 );
  $METADATA_CACHE{$DATA->{'play'}} = $DATA;

  return;
}

sub _gotMetadataError {
	my $http   = shift;
	my $client = $http->params('client');
	my $url    = $http->params('url');
	my $error  = $http->error;

	$log->is_debug && $log->debug( "Error fetching Web API metadata: $error" );

	$client->master->pluginData( webapifetchingMeta => 0 );

	# To avoid flooding the BBC servers in the case of errors, we just ignore further
	# metadata for this station if we get an error
	my $meta = defaultMeta( $client, $url );
	$meta->{_url} = $url;

	$client->master->pluginData( webapimetadata => $meta );
}

sub fetchMetadata {
  my ( $client, $url, $mediaid ) = @_;

  my $queryUrl = "http://api.hypem.com/playlist/item/" . $mediaid . "/json/1/data.js?key=f848bd68fccf9e593a2cf098616a9e43";

  my $http = Slim::Networking::SimpleAsyncHTTP->new(
    \&_gotMetadata,
    \&_gotMetadataError,
    {
      client     => $client,
      url        => $url,
      timeout    => 30,
    },
  );

  $http->get($queryUrl);
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
	  stream_url  => $json->{'stream_url'},
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

	Slim::Networking::SimpleAsyncHTTP->new(
    sub {
	    my $http = shift;
	    $log->warn("done fetching, now parsing");

      my $menu = [];

	    my $json = eval { from_json($http->content) };
	    while ( my ($index, $entry) = each(%$json) ) {
	    	if ($index =~ /\d+/) {
		      my $menuEntry = _parseEntry($entry);

		      $METADATA_CACHE{$menuEntry->{'play'}} = _parseEntry($entry);
          my $cache = Slim::Utils::Cache->new;
          $log->info("setting ". 'hypem_meta_' . $entry->{mediaid});
          $cache->set( 'hypem_meta_' . $entry->{mediaid}, _parseEntry($entry), 86400 );

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
