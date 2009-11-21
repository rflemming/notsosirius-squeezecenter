use Sirius::Sirius;
package Sirius::Canada;
BEGIN{@ISA = qw ( Sirius );}

use strict;
use warnings;

use Digest::MD5 'md5_hex';

use constant CAPTCHA => [ '',
  'vRLCHr', 'Rk9f3b', 'tN2R1A', 'R3iwj5', 'jBjsVj', 'v3jvKg', 'iimNmx',
  'cahMYf', 'Vw3rxG', 'R7KPgK', 'RUyTUS', 'Cef11w', 'NAQbyX', 'q6EYAH',
  'tReWYs', 'fimQlm', 'U6qsi6', 'm5Wkwh', 'FpVR2T', 'CuAF1k', 'sgnUw7',
  '4N1RPP', 'ech2am', 'CtbsNQ', 'kXrPES', '1AgXSR', '5DHYSR', 'e3ru7T',
  'c1yjHE', 'FR1ltI', 'Xtn36U', 'DHEWnx', '8KePqv', '1TKVVk', 'BIY138',
  'RA6c83', 'SaluKT', 'T89gGV', 'gUPVqL', 'J4F3gi', 'BbQnjy', 'qLrRgi',
  'c3eSfa', 'yAhdN5', '3YW4WC', 'mPvBah', 'UZnHN4', 'x24GCx', 'GLdYdn',
  'DsUIMk', '7GCaEc', '1WXPNr', 'SRpRsG', 'vSlae4', 'r95Vhm', '1tGuK7',
  'wnZyD4', 'c8lj6k', 'sdQ3X4', '5FNMsi', 'Up7Rni', 'csjyJa', '9Uq5rm',
  'p9kbvj', 'Cy1iip', 'mc7y2c', 'SE3rqi', 'YmJ3Tv', 'Qr32YN', 'l3rcdJ',
  'xn33VA', 'tjxuf4', '3hLBuU', '3fntSq', 'rMYmpH', 'yvKfyR', 'bkxHDW',
  'EtUSs3', '3gA7wG', 'Yn3uUL', 'hCW9Cg', 'aLI1R7', 'wmkRRP', 'Rm3C3i',
  'CgS98N', 'xaF7cd', 'ATxch8', '8I1rDk', 'C8896y', 'SiNusq', 'AQZ3kR',
  'ARFUSP', 'hDgs72', 'Lxbg1X', '4716A3', 'gCkAqa', 'wRDWeN', 'h64fGf',
  'Cr2VPm', '66SiiF',
];

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $param = shift;

  my $self = $class->SUPER::_new($param);

  $self->{site} = 'mp.siriuscanada.ca';
  $self->{base_url} = 'http://' . $self->{site} . '/sirius/ca';

  bless($self, $class);
  return $self;
}

sub auth {
  my $self = shift;

  my ($captchaID, $captchaNum);

  # Can't do much without a username and password
  if (! $self->{username} || ! $self->{password}) {
    $self->_error("No username and/or password defined");
    return;
  }

  my $url = $self->{base_url} . '/servlet/MediaPlayer';
  my $response = $self->{http}->get($url);
  $self->_parseLogin($response->content());

  # Captcha values are checked in the parsing function since they are
  # common to both US/Canada.
  if (! $self->{token}) {
    $self->_error("Token not found");
  }

  # We can't proceed with missing info
  if ($self->{error}) {
      return;
  }

  $url = $self->{base_url} . '/servlet/MediaPlayerLogin/';
  my %params = (
    'activity' => 'login',
    'type' => $self->{type},
    'token' => $self->{token},
    'username' => $self->{username},
    'captchaID' => $self->{captchaID},
    'captcha_response' => CAPTCHA->[$self->{captchaNum}],
    'loginForm' => $self->{type},
  );

  if ($self->{type} eq 'subscriber') {
     $params{'password'} = md5_hex($self->{password});
  } elsif ($self->{type} eq 'guest') {
    $params{'encryptedPassword'} = md5_hex($self->{password});
  }
  $response = $self->{http}->post($url, \%params);
  $self->_parseLoginResponse($response->content());
}

sub getCategories {
  my $self = shift;

  if (! $self->{loggedIn}) {
    $self->auth();
  }

  my $url = $self->{base_url} . 
    '/mediaplayer/player/common/lineup/category.jsp';

  my %params = (
    'category' => '',
    'genre' => '',
    'channel' => '',
  );

  my $response = $self->{http}->get($url . '?' .
                                    Sirius::_joinQueryParams(\%params));
  return $self->_parseCategories($response->content());
}

sub getGenres {
  my $self = shift;
  my $category = shift;

  if (! $self->{loggedIn}) {
    $self->auth()
  }

  my $url = $self->{base_url} . 
    '/mediaplayer/player/common/lineup/genre.jsp';

  my %params = (
    'category' => $category,
  );

  my $response = $self->{http}->get($url . '?' .
                                    Sirius::_joinQueryParams(\%params));
  return $self->_parseGenres($response->content());
}

sub getChannels {
  my $self = shift;
  my $category = shift;
  my $genre = shift;

  if (! $self->{loggedIn}) {
    $self->auth()
  }

  my $url = $self->{base_url} . 
    '/mediaplayer/player/common/lineup/channel.jsp';

  my %params = (
    'category' => $category,
    'genre' => $genre,
  );

  my $response = $self->{http}->get($url . '?' .
                                    Sirius::_joinQueryParams(\%params));
  return $self->_parseChannels($response->content());
}

sub getStream {
  my $self = shift;
  my $channel = shift;

  if (! $self->{loggedIn}) {
    $self->auth()
  }

  my $url = $self->{base_url} . '/servlet/MediaPlayer';

  my %params = (
    'activity' => 'selectStream',
    'stream' => $channel,
    'bitrate' => $self->{bitrate},
    'token' => $self->{token}
  );

  my $response = $self->{http}->get($url . '?' .
                                    Sirius::_joinQueryParams(\%params));

  my $stream = $self->_parseStream($response->content());

  # This is a poor man's relogin/retry mechanism.  If we can't find a
  # stream it may mean we were logged out.  So mark ourselves as logged
  # out and run getStream again.  The caller() test makes sure that we
  # only do this once.
  if (! $stream && caller() ne __PACKAGE__) {
    $self->{loggedIn} = 0;
    return $self->getStream($channel);
  }
  Sirius::_debug("Stream: $stream");
  return $stream;
}

1;
