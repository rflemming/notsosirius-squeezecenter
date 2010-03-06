use Sirius::Sirius;
package Sirius::US;
BEGIN{@ISA = qw ( Sirius );}

use strict;
use warnings;

use Digest::MD5 'md5_hex';

use constant CAPTCHA => [ '',
  'wrq2', 'ltfk', '2bxh', 'mf6d', 'fexy', 'wc46', 'fyp7', 'x6aw', 'nqqd',
  'rt3k', 'kqhf', 'f2wg', 'atlx', 'qnaf', 'ca2t', 'cy36', 'xddq', 'yayf',
  '4p67', '7ekw', 'yzln', 'rhld', '4eac', 'bhka', 't4kw', 'azqe', 'rwhn',
  '7rpd', 'fywp', '7hcb', 'ar3l', 'tdkt', 'kf4y', 'yffz', 'eydh', 'ywnk',
  'nfwm', '2n4d', '634t', 'ynah', 'mhpq', 'n26m', 'ra4c', 'dr4e', 'p6cz',
  'cnaw', 'w6wm', 'wm3y', 'mrdg', '3khr', 'p6fy', 'ageh', 'ctdc', 'hdzy',
  'wnkm', 'k72h', 'k627', 'pmw2', 'mwew', 'y3ya', 'r67t', 'ndpe', 'q7mq',
  'klw2', 'pydr', 'aqkh', 'wdfw', 'ewqh', 'ttep', 'tn6r', 'p6yx', 'nrkw',
  'exeb', 'ywnz', 'mhzt', 'f7mc', 'rymy', 'mtpc', 'rc3k', 'xebn', 'ffgh',
  '6y2d', 'mbkx', '6nch', 'thyg', 'rtae', 'hwe2', '3f6d', 'dqpc', 'hacn',
  'ampy', 'mler', 'mdt2', 'qgbl', 'pdqp', 'eeyc', 'mfml', 'pq3f', 'hppc',
  'ptxc',
];

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

  my $url = $self->{base_url} . '/login/siriuslogin.action';
  my $response = $self->{http}->get($url);

  $self->_parseLogin($response->content());

  # We can't proceed with missing info
  if ($self->{error}) {
      return;
  }

  my %params = (
    'userName' => $self->{username},
    '__checkbox_remember' => 'true',
    'password' => md5_hex($self->{password}),
    'captchaEnabled' => 'true',
    'captchaID' => $self->{captchaID},
    'timeNow' => 'null',
    'captcha_response' => CAPTCHA->[$self->{captchaNum}],
  );

  # Prior to login set cookies related to account type
  my %type_cookies;
  if ($self->{type} eq 'subscriber') {
    %type_cookies = (
      'sirius_consumer_type' => 'sirius_online_subscriber',
      'sirius_login_type' => 'subscriber',
    );
  } elsif ($self->{type} eq 'guest') {
    %type_cookies = (
      'sirius_consumer_type' => 'sirius_online_guest',
      'sirius_login_type' => 'guest',
    );
  }

  foreach my $key (keys %type_cookies) {
    $self->{cookie_jar}->set_cookie(undef, $key, $type_cookies{$key},
        '/', $self->{site}, undef, 1, undef, undef, 1);
  }

  $response = $self->{http}->post($url, \%params);
  $self->_parseLoginResponse($response->content());
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
