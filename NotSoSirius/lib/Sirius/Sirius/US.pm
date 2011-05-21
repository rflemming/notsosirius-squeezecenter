use Sirius::Sirius;
package Sirius::US;
BEGIN{@ISA = qw ( Sirius );}

use strict;
use warnings;
use XML::Simple;
use Digest::MD5 'md5_hex';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $param = shift;

  my $self = $class->SUPER::_new($param);

  $self->{site} = 'www.siriusxm.com';
  $self->{base_url} = 'https://' . $self->{site} . '/userservices';

  $self->{old_site} = 'www.sirius.com';
  $self->{old_base_url} = 'http://' . $self->{old_site} .  '/player';

  $self->{xml} = new XML::Simple();

  $self->{lineup} = undef;
  $self->{sessionId} = undef;
 
  bless($self, $class);
  return $self;
}

sub auth {
  my $self = shift;

  # Can't do much without a username and password
  if (! $self->{username} || ! $self->{password}) {
    $self->_error("No username and/or password defined");
    return;
  }

  my %auth_request = (
      authenticationRequest => {
          login => $self->{username},
          consumerType => 'ump',
          currency => '840',
          password => $self->{password},
          subscriberType => undef,
      });

  my $url = $self->{base_url} . '/authentication/en-us/xml/user/login';

  my $response = $self->{http}->post($url, content =>
      $self->{xml}->XMLout(\%auth_request, noattr => 1, RootName => undef));

  my $auth_xml = $self->{xml}->XMLin($response->content());

  if ($auth_xml->{messages}->{code} == 100) {  
    $self->{sessionId} = $auth_xml->{sessionId};

    # This adds the necessary cookies to access the old WMA based
    # player.
    my %cookies = (
      'playerType' => 'sirius',
      'sirius_user_name' => $self->{username},
      'sirius_password' => md5_hex($self->{password}),
      'sirius_mp_playertype' => 'expand',
      'sirius_mp_bitrate_entitlement_cookie' => $self->{bitrate},
      'sirius_mp_bitrate_button_status_cookie' => $self->{bitrate},
      'sirius_login_attempts' => 0,
      'sirius_consumer_type' => 'sirius_online_' . $self->{type},
      'sirius_login_type' => $self->{type},
    );

    # Type is reassigned here from the configured value for our plugin
    # to the value as returned by login.  The configured type value is
    # no longer used at this point since it's only for the old player.
    $self->{type} = $auth_xml->{userInfo}->{account}->{subscriberType};

    foreach my $key (keys %cookies) {
      $self->{cookie_jar}->set_cookie(undef, $key, $cookies{$key},
          '/', $self->{old_site}, undef, 1, undef, undef, 1);
    }

    $self->{loggedIn} = 1;
    Sirius::_debug("Logged In");
  } else {
    $self->_error($auth_xml->{messages}->{message});
  }

  if ($self->{error}) {
      return;
  }

  if (! $self->{lineup}) {
    $self->{lineup} = $self->_getLineup(
        $auth_xml->{userInfo}->{account}->{channelLineupId});
  }
}

sub _getLineup {
  my $self = shift;
  my $channelLineupId = shift;

  my $url =
      $self->{base_url} .  '/cl/en-us/xml/lineup/' .
      $channelLineupId .  '/client/UMP';

  my $response = $self->{http}->get($url);

  my $lineup_xml = $self->{xml}->XMLin($response->content(),
                                       keyattr=> ['key', 'channelKey'],
                                       forcearray => ['genres', 'channels']);

  if ($lineup_xml->{messages}->{code} == 100) {
    return $lineup_xml->{lineup};
  } else {
    $self->_error($lineup_xml->{messages}->{message});
  }
}

sub getCategories {
  my $self = shift;

  my %categories = ();
  my $category_ref = $self->{lineup}->{categories};
  foreach my $c (keys %{$category_ref}) {
    my $category = $category_ref->{$c};
    $categories{$c} = $category->{name};
  }
  return %categories;
}

sub getGenres {
  my $self = shift;
  my $category = shift;

  my %genres = ();
  my $genre_ref = $self->{lineup}->{categories}->{$category}->{genres};
  foreach my $g (keys %{$genre_ref}) {
    my $genre = $genre_ref->{$g};
    $genres{$g} = $genre->{name};
  }
  return %genres;
}

sub getChannels {
  my $self = shift;
  my $category = shift;
  my $genre = shift;

  my %channels = ();
  my $channel_ref = $self->{lineup}->{categories}->{$category}->{genres}->{$genre}->{channels};
  my @children;
  foreach my $c (keys %{$channel_ref}) {
    my $channel = $channel_ref->{$c};
  
    # Skip channels we don't get and channels which don't work in the
    # old player.  Verify that each discovered channel works by
    # attempting to fetch the stream.  This will be slow, but it's not
    # something that should be done frequently.
    if (($channel->{isAvailable} eq "false") || 
        (! $self->_getStream($c, $genre, $category))) {
      Sirius::_debug(
          "Skipping channel:  $c - $channel->{name}");
      next;
    }
  
    $channels{$c}->{category} = $category;
    $channels{$c}->{genre} = $genre;
    $channels{$c}->{key} = $c;
    Sirius::_debug("Channel: $channels{$c}->{key}");
    if ($self->{type} eq 'SIRIUS_SUBSCRIBER') {
      $channels{$c}->{number} = $channel->{siriusChannelNo};
    } elsif ($self->{type} eq 'XM_SUBSCRIBER') {
      $channels{$c}->{number} = $channel->{xmChannelNo};
    }
    Sirius::_debug("  Number: $channels{$c}->{number}");
    $channels{$c}->{name} = $channel->{name};                                                             
    Sirius::_debug("  Name: $channels{$c}->{name}");
    $channels{$c}->{desc} = $channel->{description};
    Sirius::_debug("  Desc: $channels{$c}->{desc}");
    foreach my $l (@{$channel->{logos}}) {
      if ($l->{resourceType} eq 'channelbrowse') {
        $channels{$c}->{logo} = $l->{url};
        Sirius::_debug("  Logo: $channels{$c}->{logo}");
      }
    }
  }
  return %channels;
}

sub _getStream {
  my $self = shift;
  my $channel = shift;
  my $genre = shift;
  my $category = shift;

  my $stream = '';

  my $url = $self->{old_base_url} . '/listen/play.action';

  my %params = (
    'channelKey' => $channel,
    'genreKey' => $genre,
    'categoryKey' => $category,
    'stopped' => 'no',
  );

  my $response = $self->{http}->get($url . '?' .
                                    Sirius::_joinQueryParams(\%params));
  my $asxfwrd  = $self->_parseStream($response->content());
  if ($asxfwrd) {
    $asxfwrd = 'http://' . $self->{old_site} . $asxfwrd;

    $response = $self->{http}->get($asxfwrd);
    # Had a wierd case of getting back a URL for the previously
    # requested channel when asking for a channel that wasn't available.
    # Search for the channel key specifically in the response.
    if ($response->content() =~ m/http:\/\/.+&stream=$channel&.+\.asx/) {
      $stream = $response->content();
    }
  }
  return $stream;
}

sub getStream {
  my $self = shift;

  if (! $self->{loggedIn}) {
    $self->auth()
  }

  my $stream = $self->_getStream(@_);

  # This is a poor man's relogin/retry mechanism.  If we can't find a
  # stream it may mean we were logged out.  So mark ourselves as logged
  # out and run getStream again.  The caller() test makes sure that
  # we only do this once.
  if (! $stream and caller() ne __PACKAGE__) {
    $self->{loggedIn} = 0;
    Sirius::_debug("Unable to get stream, retrying...");
    return $self->getStream(@_);
  }
  Sirius::_debug("Stream: $stream");
  return $stream;
}

1;
