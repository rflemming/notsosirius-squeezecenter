use Sirius::Sirius;
package Sirius::US;
BEGIN{@ISA = qw ( Sirius );}

use strict;
use warnings;

use Digest::MD5 'md5_hex';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $param = shift;

  my $self = $class->SUPER::_new($param);

  $self->{site} = 'www.sirius.com';
  $self->{base_url} = 'http://' . $self->{site} .  '/player';

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

  foreach my $key (keys %cookies) {
    $self->{cookie_jar}->set_cookie(undef, $key, $cookies{$key},
        '/', $self->{site}, undef, 1, undef, undef, 1);
  }

  # Since no actual login process is taking place simply assume we are
  # logged in after setting all of the above cookies.
  $self->{loggedIn} = 1
}

sub _getFwrdAction {
  my $self = shift;
  my $category = shift || '';
  my $genre = shift || '';

  if (! $self->{loggedIn}) {
    $self->auth();
  }

  my $url = $self->{base_url} . '/channel/fwrd.action';
  my %params = (
    'categoryKey' => $category,
    'genreKey' => $genre,

  );

  if ($genre && $category) {
    $params{'pageName'} = 'channel';
  } elsif ($category) {
    $params{'pageName'} = 'genre';
  } else {
    $params{'pageName'} = 'category';
  }

  my $response = $self->{http}->get($url . '?' .
                                    Sirius::_joinQueryParams(\%params));
  return $response->content();
}

sub getCategories {
  my $self = shift;

  return $self->_parseCategories($self->_getFwrdAction());
}

sub getGenres {
  my $self = shift;
  my $category = shift;

  return $self->_parseGenres($self->_getFwrdAction($category));
}

sub getChannels {
  my $self = shift;
  my $category = shift;
  my $genre = shift;

  return $self->_parseChannels($self->_getFwrdAction($category, $genre));
}

sub getStream {
  my $self = shift;
  my $channel = shift;
  my $genre = shift;
  my $category = shift;

  if (! $self->{loggedIn}) {
    $self->auth()
  }
  my $stream = '';

  my $url = $self->{base_url} . '/listen/play.action';

  my %params = (
    'channelKey' => $channel,
    'genreKey' => $genre,
    'categoryKey' => $category,
    'stopped' => 'no',
  );

  # In the new player, bitrate is set via cookie
  $self->{cookie_jar}->set_cookie(
      undef, 'sirius_mp_bitrate_button_status_cookie', $self->{bitrate},
      '/', $self->{site}, undef, 1, undef, undef, 1);

  my $response = $self->{http}->get($url . '?' .
                                    Sirius::_joinQueryParams(\%params));

  my $asxfwrd  = $self->_parseStream($response->content());
  # Unlike in the old style media player, the value returned is not
  # the direct link to the mms stream.  You must first retrieve that
  # URL, and that page will contain the link to the actual stream.
  if ($asxfwrd) {
    if ($asxfwrd !~ /^http/) {
      $asxfwrd = 'http://' . $self->{site} . $asxfwrd;
    }

    $response = $self->{http}->get($asxfwrd);
    if ($response->content() =~ m/http:\/\/.*\.asx/) {
      $stream = $response->content();
    }
  }

  # This is a poor man's relogin/retry mechanism.  If we can't find a
  # stream it may mean we were logged out.  So mark ourselves as logged
  # out and run getStream again.  The caller() test makes sure that
  # we only do this once.
  if (! $stream and caller() ne __PACKAGE__) {
    $self->{loggedIn} = 0;
    Sirius::_debug("Unable to get stream, retrying...");
    return $self->getStream($channel, $genre, $category);
  }
  Sirius::_debug("Stream: $stream");
  return $stream;
}

1;
