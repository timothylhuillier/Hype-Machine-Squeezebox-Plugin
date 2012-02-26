package Plugins::HypeM::ProtocolHandler;

use strict;

use base qw(Slim::Player::Protocols::HTTP);

use List::Util qw(min max);
use LWP::Simple;
use LWP::UserAgent;
use HTML::Parser;
use URI::Escape;
use JSON::XS::VersionOneAndTwo;
use XML::Simple;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Errno;
use Slim::Utils::Cache;
use Scalar::Util qw(blessed);

my $log   = logger('plugin.hypem');
my $prefs = preferences('plugin.hypem');

my %fetching; # hash of ids we are fetching metadata for to avoid multiple fetches

Slim::Player::ProtocolHandlers->registerHandler('hypem', __PACKAGE__);

use strict;
use base 'Slim::Player::Protocols::HTTP';

sub _parseEntry {
  my $json = shift;

  my $DATA = {
    duration => int($json->{'time'}),
    mediaid => $json->{'mediaid'},
    name => $json->{'title'},
    title => $json->{'title'},
    artist => $json->{'artist'},
    play => $json->{'stream_url_raw'},
    #url  => $json->{'permalink_url'},
    link => $json->{'stream_url_raw'},
    icon => $json->{'thumb_url_large'} || "",
    image => $json->{'thumb_url_large'} || "",
    cover => $json->{'thumb_url_large'} || "",
  };
}

sub canSeek { 1 }

sub getFormatForURL () { 'mp3' }

sub isRemote { 1 }

sub scanUrl {
  my ($class, $url, $args) = @_;
  $args->{cb}->( $args->{song}->currentTrack() );
}

sub getNextTrack {
  my ($class, $song, $successCb, $errorCb) = @_;
  
  my $client = $song->master();
  my $url    = $song->currentTrack()->url;
  
  # Get next track
  my ($id) = $url =~ m{^hypem://(.*)$};

  my $cache = Slim::Utils::Cache->new;
  my $meta      = $cache->get( 'hypem_meta_' . $id );

  if ($meta) {
    gotNextTrackHelper($successCb, $errorCb, $client, $song, $meta);
    return;
  }

  # Talk to SN and get the next track to play
#     pecific Track Metadata (returns 1 item)
# http://api.hypem.com/playlist/item/1ad2j/json/1/data.js
# Arbitrarily-constructed list of tracks
# http://api.hypem.com/playlist/set/1ad2j,1ahkc/json/1/data.js
  my $trackURL = addClientId("http://api.hypem.com/playlist/item/" . $id . "/json/1/data.js");
  
  my $http = Slim::Networking::SimpleAsyncHTTP->new(
          \&gotNextTrack,
          \&gotNextTrackError,
          {
                  client        => $client,
                  song          => $song,
                  callback      => $successCb,
                  errorCallback => $errorCb,
                  timeout       => 35,
          },
  );
  
  main::DEBUGLOG && $log->is_debug && $log->debug("Getting track from hypem for $id");
  
  $http->get( $trackURL );
}

sub gotNextTrack {
  my $http   = shift;
  my $client = $http->params->{client};
  my $song   = $http->params->{song};     
  my $track  = eval { from_json( $http->content ) };
  my $meta = _parseEntry($track);

  my $cache = Slim::Utils::Cache->new;
  $log->info("setting ". 'hypme__meta_' . $track->{mediaid});
  $cache->set( 'hypem_meta_' . $track->{mediaid}, $meta, 86400 );

  gotNextTrackHelper($http->params->{callback},
    $http->params->{'errorCallback'}, $client, $song, $meta)
}

sub gotNextTrackHelper {
  my $callback   = shift;
  my $errorCallback = shift;
  my $client = shift;
  my $song   = shift;
  my $meta  = shift;

  # if ( $@ || $track->{error} ) {
  #   # We didn't get the next track to play
  #   if ( $log->is_warn ) {
  #     $log->warn( 'hypem error getting next track: ' . ( $@ || $track->{error} ) );
  #   }
    
  #   if ( $client->playingSong() ) {
  #     $client->playingSong()->pluginData( {
  #         songName => $@ || $track->{error},
  #     } );
  #   }
    
  #   $errorCallback->( 'PLUGIN_HYPEM_NO_INFO', $track->{error} );
  #   return;
  # }

  # Save metadata for this track
  $song->pluginData( $meta );

  $log->info($meta->{stream_url});
  $song->streamUrl($meta->{stream_url});
  $song->duration( $meta->{duration} );

  $callback->();
}

sub gotNextTrackError {
  my $http = shift;
  
  $http->params->{errorCallback}->( 'PLUGIN_SOUNDCLOUD_ERROR', $http->error );
}

# To support remote streaming (synced players, slimp3/SB1), we need to subclass Protocols::HTTP
sub new {
  my $class  = shift;
  my $args   = shift;

  my $client = $args->{client};
  
  my $song      = $args->{song};
  my $streamUrl = $song->streamUrl() || return;
  my $track     = $song->pluginData();
  
  $log->info( 'Remote streaming hypem track: ' . $streamUrl );

  my $sock = $class->SUPER::new( {
    url     => $streamUrl,
    song    => $song,
    client  => $client,
  } ) || return;
  
  ${*$sock}{contentType} = 'audio/mpeg';

  return $sock;
}


# Track Info menu
sub trackInfo {
  my ( $class, $client, $track ) = @_;
  
  my $url = $track->url;
  $log->info("trackInfo: " . $url);
}

# Track Info menu
sub trackInfoURL {
  my ( $class, $client, $url ) = @_;
  $log->info("trackInfoURL: " . $url);
}

use Data::Dumper;
# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
  my ( $class, $client, $url ) = @_;
    
  return {} unless $url;

  #$log->info("metadata: " . $url);

  my $icon = $class->getIcon();
  my $cache = Slim::Utils::Cache->new;

	# If metadata is not here, fetch it so the next poll will include the data
	my ($trackId) = $url =~ m{hypem://(.+)};
	#$log->info("looking for  ". 'soundcloud_meta_' . $trackId );
	my $meta      = $cache->get( 'hypem_meta_' . $trackId );

	if ( !$meta && !$client->master->pluginData('fetchingMeta') ) {
    # Go fetch metadata for all tracks on the playlist without metadata
    my @need;
    
    for my $track ( @{ Slim::Player::Playlist::playList($client) } ) {
	    my $trackURL = blessed($track) ? $track->url : $track;
	    if ( $trackURL =~ m{hypem://(.+)} ) {
        my $id = $1;
        if ( !$cache->get("hypem_meta_$id") ) {
          push @need, $id;
        }
	    }
    }
    
    if ( main::DEBUGLOG && $log->is_debug ) {
      $log->debug( "Need to fetch metadata for: " . join( ', ', @need ) );
    }
    
    $client->master->pluginData( fetchingMeta => 1 );

    # http://api.hypem.com/playlist/set/1ad2j,1ahkc/json/1/data.js

    
    my $metaUrl = Slim::Networking::SqueezeNetwork->url(
            "/api/classical/v1/playback/getBulkMetadata"
    );

    my $queryUrl = "http://api.hypem.com/playlist/set/" . join( ', ', @need ) . "/json/data.js?key=f848bd68fccf9e593a2cf098616a9e43";

  $log->warn("fetching: $queryUrl");

    Slim::Networking::SimpleAsyncHTTP->new(
      \&_gotBulkMetadata,
      \&_gotBulkMetadataError,
      {
        client  => $client,
        timeout => 60,
      },
    )->get($queryUrl);
	}

	#$log->debug( "Returning metadata for: $url" . ($meta ? '' : ': default') );

	return $meta || {
	        type      => 'MP3 (Hype Machine)',
	        icon      => $icon,
	        cover     => $icon,
	};
}

sub _gotBulkMetadata {
  my $http   = shift;
  my $client = $http->params->{client};
  
  $client->master->pluginData( fetchingMeta => 0 );
  
  my $json = eval { from_json( $http->content ) };
          
  # Cache metadata
  my $cache = Slim::Utils::Cache->new;
  my $icon  = Slim::Plugin::HypeM::Plugin->_pluginDataFor('icon');

  while ( my ($index, $entry) = each(%$json) ) {
    if ($index =~ /\d+/) {
      my $menuEntry = _parseEntry($entry);

      my $cache = Slim::Utils::Cache->new;
      $log->info("setting ". 'hypem_meta_' . $entry->{mediaid});
      $cache->set( 'hypem_meta_' . $entry->{mediaid}, _parseEntry($entry), 86400 );
    }
  }

  # Update the playlist time so the web will refresh, etc
  $client->currentPlaylistUpdateTime( Time::HiRes::time() );
  
  Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );        
}

sub _gotBulkMetadataError {
  my $http   = shift;
  my $client = $http->params('client');
  my $error  = $http->error;
  
  $client->master->pluginData( fetchingMeta => 0 );
  
  $log->warn("Error getting track metadata from SN: $error");
}

sub canDirectStreamSong {
  my ( $class, $client, $song ) = @_;
  
  # We need to check with the base class (HTTP) to see if we
  # are synced or if the user has set mp3StreamingMethod
	return $class->SUPER::canDirectStream( $client, $song->streamUrl(), $class->getFormatForURL() );
}

# If an audio stream fails, keep playing
sub handleDirectError {
  my ( $class, $client, $url, $response, $status_line ) = @_;
  
  main::INFOLOG && $log->info("Direct stream failed: $url [$response] $status_line");
  
  $client->controller()->playerStreamingFailed( $client, 'PLUGIN_CLASSICAL_STREAM_FAILED' );
}

1;
