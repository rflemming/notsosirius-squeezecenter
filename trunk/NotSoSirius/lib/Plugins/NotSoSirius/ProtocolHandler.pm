package Plugins::NotSoSirius::ProtocolHandler;

# $Id$

use strict;
use base qw(Slim::Player::Protocols::MMS);

use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('plugin.notsosirius');

sub audioScrobblerSource { 'R' }

sub getFormatForURL { 'wma' }

sub isAudioURL { 1 }

sub isRemote { 1 }

# Support transcoding
sub new {
	my $class = shift;
	my $args  = shift;

  my $streamUrl;
  if ($::VERSION lt '7.4') {
    $streamUrl = $args->{'song'}->{'streamUrl'};
  } else {
    $streamUrl = $args->{'song'}->streamUrl();
  }

	my $url = $streamUrl;
	
	return unless $url;
	
	$args->{'url'} = $url;

	return $class->SUPER::new($args);
}

sub getNextTrack {
	my ($class, $song, $successCb, $errorCb) = @_;
	
	if ( main::SLIM_SERVICE ) {
		# Fail if firmware doesn't support metadata
		my $client = $song->master();
		my $old;
		
		my $deviceid = $client->deviceid;
		my $rev      = $client->revision;
		
		if ( $deviceid == 4 && $rev < 119 ) {
			$old = 1;
		}
		elsif ( $deviceid == 5 && $rev < 69 ) {
			$old = 1;
		}
		elsif ( $deviceid == 7 && $rev < 54 ) {
			$old = 1;
		}
		elsif ( $deviceid == 10 && $rev < 39 ) {
			$old = 1;
		}
		
		if ( $old ) {
			$errorCb->('PLUGIN_NOTSOSIRIUS_FIRMWARE_UPGRADE_REQUIRED');
			return;
		}
	}
	
	my ($channelId) = $song->currentTrack()->url =~ m{^sirius://(.+)};
  Plugins::NotSoSirius::Plugin::getStream($song->master(), $channelId, $successCb, $song);
}

sub canDirectStreamSong {
	my ( $class, $client, $song ) = @_;

  my $streamUrl;
  if ($::VERSION lt '7.4') {
    $streamUrl = $song->{'streamUrl'};
  } else {
    $streamUrl = $song->streamUrl();
  }

  return $class->SUPER::canDirectStream($client, $streamUrl, $class->getFormatForURL());

}

sub parseDirectHeaders {
	my $class   = shift;
	my $client  = shift || return;
	my $url     = shift;
#	my @headers = @_;
	
	my $contentType = 'wma';
	my $bitrate     = $client->streamingSong()->bitrate();

	# title, bitrate, metaint, redir, type, length, body
	return (undef, $bitrate, 0, undef, $contentType, undef, undef);
}

sub parseMetadata {
	my ( $class, $client, $song, $metadata ) = @_;
	
	# If we have ASF_Command_Media, process it here, otherwise let parent handle it
	my $guid;
	map { $guid .= $_ } unpack( 'H*', substr $metadata, 0, 16 );
	
	if ( $guid ne '59dacfc059e611d0a3ac00a0c90348f6' ) { # ASF_Command_Media
		return $class->SUPER::parseMetadata( $client, $song, $metadata );
	}
	
	substr $metadata, 0, 24, '';
		
	# Format of the metadata stream is:
	# TITLE <title>|ARTIST <artist>\0
	
	# WMA text is in UTF-16, if we can't decode it, just wait for more data
	# Cut off first 24 bytes (16 bytes GUID and 8 bytes object_size)
	$metadata = eval { Encode::decode( 'UTF-16LE', $metadata ) } || return;
	
	#$log->debug( "ASF_Command_Media: $metadata" );
	
	my ($artist, $title);
	
	if ( $metadata =~ /TITLE\s+([^|]+)/ ) {
		$title = $1;
	}
	
	if ( $metadata =~ /ARTIST\s([^\0]+)/ ) {
		$artist = $1;
	}
	
	if ( $artist || $title ) {
		if ( $artist && $artist ne $title ) {
			$title = "$artist - $title";
		}
		
		# Delay the title by the length of the output buffer only
		Slim::Music::Info::setDelayedTitle( $song->master(),  $song->currentTrack()->url, $title, 'output-only' );
	}
	
	return;
}

# Metadata for a URL, used by CLI/JSON clients
sub getMetadataFor {
	my ( $class, $client, $url ) = @_;

	my ($artist, $title);
	# Return artist and title if the metadata looks like Artist - Title
	if ( my $currentTitle = Slim::Music::Info::getCurrentTitle( $client, $url ) ) {
		my @dashes = $currentTitle =~ /( - )/g;
		if ( scalar @dashes == 1 ) {
			($artist, $title) = split / - /, $currentTitle;
		}

		else {
			$title = $currentTitle;
		}
	}

	# try to find song
	my $song = $client->streamingSong();

	my $bitrate;
	my $logo;

  my $streamUrl;
  if ($::VERSION lt '7.4') {
    $streamUrl = $song->{'streamUrl'};
  } else {
    $streamUrl = $song->streamUrl();
  }

	if ($song && ($song->currentTrack()->url eq $url || $streamUrl eq $url)) {
		$bitrate = ($song->bitrate || 0) / 1000;
		my ($channelId) = $url =~ m{^sirius://(.+)};
		$logo = Plugins::NotSoSirius::Plugin::getChannelImage($channelId);
	}
	$bitrate ||= 128;
	$logo ||= $class->getIcon($url);
	return {
		artist  => $artist,
		title   => $title,
		cover   => $logo,
		bitrate => $bitrate . 'k CBR',
		type    => 'WMA (Sirius)',
	};
}

sub getIcon {
	return Plugins::NotSoSirius::Plugin->_pluginDataFor('icon');
}

1;
