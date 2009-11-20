package Plugins::NotSoSirius::Plugin;

# Copyright 2009 Robert Flemming (flemming@spiralout.net)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use warnings;

use HTML::Entities;

use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

use Plugins::NotSoSirius::Settings;

use Sirius::Sirius;

use base qw(Slim::Plugin::OPMLBased);

my $prefs = preferences('plugin.notsosirius');

my $log = Slim::Utils::Log->addLogCategory({
  'category'     => 'plugin.notsosirius',
  'defaultLevel' => 'ERROR',
  'description'  => getDisplayName(),
});

# Maintain our Sirius instance globally
my $sirius;

# genreMap maps genre's to an array of channel keys, channelMap maps
# channel keys to channel objects;
my ($genreMap, $channelMap);

# When using OPML 'image' items must be fully qualified URLs for images
# to appear on the duet controller.  So we need to figure our IP and
# port.  Theoretically Slim::Utils::IPDetect::IP_port() does this, but
# it wasn't returning the port number.
my $ip_port = Slim::Utils::IPDetect::IP() . ':' .  
                preferences('server')->get('httpport');

sub initPlugin {
  my $class = shift;

  Plugins::NotSoSirius::Settings->new;

  Slim::Player::ProtocolHandlers->registerHandler(
      sirius => 'Plugins::NotSoSirius::ProtocolHandler'
  );

  my $accountRef = $prefs->get('account') || '';
  if ($accountRef) {
    my $account = @{$accountRef}[0];
    $sirius = Sirius->new($account);
    $sirius->auth();
    ($genreMap, $channelMap) = {};
  } else {
    $sirius->{error} = "Plugin not configured"
  }

  $class->SUPER::initPlugin(
      tag            => 'notsosirius',
      menu           => 'radios',
      weight         => 50,
  );

  if ( main::SLIM_SERVICE ) {
    my $menu = {
      useMode => sub { $class->setMode(@_) },
      header  => string('PLUGIN_NOTSOSIRIUS'),
    };

    Slim::Buttons::Home::addSubMenu(
        'RADIO',
        'PLUGIN_NOTSOSIRIUS',
        $menu,
    );

    $class->initCLI(
        tag  => 'notsosirius_radio',
        menu => 'radios',
    );
  }
}

sub feed {
  my $class = shift;

  my @opml;
  if ($sirius->{error}) {
    @opml = ($class->Error());
  } else {
    # Go through the slow painful process of building the genre and
    # channel maps if we don't already have them
    if (! ($genreMap && $channelMap)) {
      ($genreMap, $channelMap) = &getGenreChannelMap();
    }

    push(@opml, {
      'name' => 'By Channel Name',
      'type' => 'opml',
      'items' => [&OPMLByName()],
    }, {
      'name' => 'By Channel Number',
      'type' => 'opml',
      'items' => [&OPMLByNumber()],
    });
    @opml = (@opml, &OPMLByGenre());
  }

  # Dance around button mode stuff.  I don't really understand it, but
  # it works so woohoo.
  my $caller = (caller(1))[3];
  if ($caller =~ /setMode/) {
    return sub { $_[1]->(\@opml) };
  } else {
    return { title => string('PLUGIN_NOTSOSIRIUS'), items => \@opml };
  }
}

sub Error {
  my $class = shift;
  my $error = shift;

  # First use the internal NotSoSirius message, then the user specified one
  # so that we can catch all errors with a single test while browsing.
  if ($sirius->{error}) {
    $error = $sirius->{error};
  } elsif (! $error) {
    $error = "Unknown error";
  }

  # Log the error and return it is a feed item.  Clicking it won't do
  # much, but it's the only way to return the error
  $log->info($error);

  return {'name' => $error};
}

sub getDisplayName {
  return 'PLUGIN_NOTSOSIRIUS';
}

sub playerMenu () {
  return 'RADIO';
}

sub getStream {
  my $client = shift;
  my $key = shift;
  my $callback = shift;
  my $song = shift;
 
  my $channel = $channelMap->{$key};

  # Only the US site requires all of these, the Canada site only needs
  # the channel key value, the others are ignored
  my $stream = $sirius->getStream(
    $channel->{key}, $channel->{genre}, $channel->{category});

  $stream =~ s/^http/mms/;
  $log->debug("Streaming: $stream\n");

  if ($::VERSION lt '7.4') {
    $song->{'streamUrl'} = $stream;
    $song->{'wmaMetadataStream'} = 2;
  } else {
    $song->streamUrl($stream);
    $song->wmaMetadataStream(2);
  }

  $callback->();
  return;
}

sub getGenreChannelMap {
  my (%genreMap, %channelMap);

  my %categories = $sirius->getCategories();
  foreach my $c (keys %categories) {
    # Convert the category name to 'title' case
    (my $category = $categories{$c}) =~ s/(\w+)/\u\L$1/g;

    # We want to colapse the 3 tier menu system on the Sirius website into a 2
    # tier menu system by pulling the genres under the 'MUSIC' category up a
    # level.  @category_channels are essentially the non-music channels, while
    # @genre_channels are the music channels which fall under each genre.

    my @category_channels;
    my %genres = $sirius->getGenres($c);
    foreach my $g (keys %genres) {
      my $genre = $genres{$g};

      my @genre_channels;
      my %channels = $sirius->getChannels($c, $g);
      foreach my $n (keys %channels) {
        my $channel = $channels{$n};
        $channel->{key} = $n;
        # Add the category and genre keys as attributes
        $channel->{category} = $c;
        $channel->{genre} = $g;
        $channelMap{$n} = $channel;
        push(@genre_channels, $n);
      }
      if ($category eq 'Music') {
        # Group the music channels by genre
        $genreMap{$genre} = \@genre_channels;
      } else {
        @category_channels = (@genre_channels, @category_channels);
      }
    }
    # Group the non-music channels by category
    if ($category ne 'Music') {
    	$genreMap{$category} = \@category_channels;
    }
  }
  return (\%genreMap, \%channelMap);
}

sub getChannelImage {
  my $channel = shift;

  return 'http://' . $ip_port . 
         '/plugins/NotSoSirius/html/images/' . $channel . '.png';
}

sub OPMLByNumber {
  my @opml;
  my %channelMap = %{$channelMap};

  foreach my $key (keys %channelMap) {
    my $channel = $channelMap{$key};
    push(@opml, {
      'name' => $channel->{number}.'. '.$channel->{name},
      'description' => $channel->{desc},
      'type' => 'audio',
      'image' => &getChannelImage($channel->{key}),
      'url' => 'sirius://' . $channel->{key},
    });
  }
  return sort { (split('\.', $a->{name}))[0] <=> (split('\.', $b->{name}))[0] } @opml;
}

sub OPMLByName {
  my @opml;
  my %channelMap = %{$channelMap};

  foreach my $key (keys %channelMap) {
    my $channel = $channelMap{$key};
    push(@opml, {
      'name' => $channel->{name},
      'description' => $channel->{desc},
      'type' => 'audio',
      'image' => &getChannelImage($channel->{key}),
      'url' => 'sirius://' . $channel->{key},
    });
  }
  return sort { $a->{name} cmp $b->{name} } @opml;
}

sub OPMLByGenre {
  my @opml;

  my %genreMap = %{$genreMap};
  my %channelMap = %{$channelMap};

  foreach my $genre (keys %genreMap) {
    my @channels;
    foreach my $key (@{$genreMap{$genre}}) {
      my $channel = $channelMap{$key};
      push(@channels, {
        'name' => $channel->{number}.'. '.$channel->{name},
        'description' => $channel->{desc},
        'type' => 'audio',
        'image' => &getChannelImage($channel->{key}),
        'url' => 'sirius://' . $channel->{key},
      });  
    }
    @channels = sort { (split('\.', $a->{name}))[0] <=> (split('\.', $b->{name}))[0] } @channels;
    push(@opml, {
      'name' => $genre,
      'type' => 'opml',
      'items' => \@channels,
    });
  }
  return sort { $a->{name} cmp $b->{name} } @opml;
}

1;
