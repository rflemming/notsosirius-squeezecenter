package Sirius;

use strict;
use warnings;

use LWP::ConnCache;
use LWP::UserAgent::Determined;
use HTML::Entities;
use HTTP::Cookies;
use Sirius::Sirius::US;
use Sirius::Sirius::Canada;

my $debug = 0;

# Write debugging to STDERR
sub _debug {
  my $msg = shift;
  if ($debug) {
    print STDERR "DEBUG: $msg\n";
  }
}

# Take a hash of query parameters and join for use via GET
sub _joinQueryParams {
  my $params = shift;
  my %params = %{$params};

  return join('&',
              map {"$_=$params{$_}" if defined($params{$_})} keys %params);
}

# This is sort of a faux constructor in that we simply use to avoid
# needing to include both the US and Canada modules elsewhere.  The real
# constructor is _new() which is called via SUPER in the subclass.
sub new {
  my $self = {};
  my $class = shift;
  my $param = shift;

  if ($param->{country} && $param->{country} eq 'Canada') {
    return Sirius::Canada->new($param);
  } else {
    return Sirius::US->new($param);
  }
}

sub debug {
  my $self = shift;
  $debug = shift;
}

sub _new {
  my $self = {};
  my $class = shift;
  my $param = shift;

  $self->{username} = undef;
  $self->{password} = undef;
  $self->{type} = 'subscriber';
  $self->{bitrate} = 'low';
  $self->{token} = undef;
  $self->{error} = undef;
  $self->{loggedIn} = 0;

  # Override the default parameters if others are passed
  if (ref($param)) {
    my %params = %{$param};
    foreach my $key (keys %params) {
      $self->{$key} = $params{$key};
    }
  }

  # LWP::UserAgent::Determined saves me from writing extra retry code.
  $self->{http} = LWP::UserAgent::Determined->new();
  $self->{http}->agent('Mozilla/5.0 (X11; U; Linux x86_64; en-US;) ' .
                       'Gecko/2009102815 SqueezeboxServer/NotSoSirius');

  # Storing cookies in memory is sufficient
  $self->{cookie_jar} = HTTP::Cookies->new({});
  $self->{http}->cookie_jar($self->{cookie_jar});

  # Try to reuse existing connections.  I've seen this cause problems,
  # but LWP::UserAgent::Determined should help with that and this should
  # make things faster.
  $self->{http}->conn_cache(LWP::ConnCache->new());

  # How many times and how long we should wait before retrying
  $self->{http}->timing('1,1,1,2,2,3');
  # Verify and log how our request panned out
  $self->{http}->after_determined_callback(
      sub {
        my $delay = $_[2];
        my $request = $_[4][0];
        my $response = $_[5];
        if (! $delay) {
          $self->_error("Request for $request->uri failed with code: " .
                        "$response->code()");
        } elsif (! $response->is_success) {
          _debug("Retry due to response code: " . $response->code() . ", " .
                 "waiting $delay seconds.");
        } else {
          $self->{error} = undef;
        }
      });

  bless($self);
  return $self;
}

# Log and save error messages
sub _error {
  my $self = shift;
  my $msg = shift;

  $self->{error} = $msg;
  if ($debug) {
    print STDERR "ERROR: $self->{error}\n";
  }
}

# Extract the necessary bits into order to login
sub _parseLogin {
  my $self = shift;
  my $content = shift;

  foreach my $line (split(/\r?\n/, $content)) {
    if ($line =~ /bg-now-playing-mac-large/) {
      $self->{loggedIn} = 1;
      _debug("Already logged in");
      return;
    } elsif ($line =~ /name="token" value="(.*)"/) {
     $self->{token} = $1;
     _debug("Token: $self->{token}");
    } elsif ($line =~ /name="captchaID" value="(.+)"/) {
      $self->{captchaID} = $1;
      _debug("ID: $self->{captchaID}");
    } elsif ($line =~ /img src=".*\/img_(\d{2,4})\.jpg"/) {
      $self->{captchaNum} = int($1);
      _debug("Captcha Number: $self->{captchaNum}");
    }
  }

  if (! $self->{captchaID}) {
    $self->_error("CaptchaID not found");
  } elsif (! $self->{captchaNum}) {
    $self->_error("Captcha number not found");
  }
}

# Parse the post-login page to make sure things worked out
sub _parseLoginResponse {
  my $self = shift;
  my $content = shift;

  foreach my $line (split(/\r?\n/, $content)) {
    if ($line =~ /text does not match the image/) {
      $self->_error("Captcha mismatch");
    } elsif ($line =~ /Password or Username error/) {
      $self->_error("Login failed, incorrect username/password");
    } elsif ($line =~ /an error has occurred/) {
      $self->_error("Unknown login error");
    } elsif ($line =~ /Insufficient Access/) {
      $self->_error("Your account has no stream access");
    }
  }

  # If there was an error we'll display it via feed()
  if (! $self->{error}) {
    $self->{loggedIn} = 1;
    _debug("Logged In");
  }
}

# Extract categories from the HTML
sub _parseCategories {
  my $self = shift;
  my $content = shift;
  my %categories = ();

  foreach my $line (split/\r?\n/, $content) {
    if ($line =~ /myPlayer.Category\('(.+)?',.*>(.+)</) {
      $categories{$1} = decode_entities($2);
    }
  }

  if (%categories) {
    $self->{error} = undef;
  } else {
    $self->_error("No categories found. Logged in?");
    $self->{loggedIn} = 0;
  }

  return %categories
}

# Extract genres from the HTML
sub _parseGenres {
  my $self = shift;
  my $content = shift;
  my %genres = ();

  # Match everything at once since content is now spread across multiple
  # lines we can't just loop over the page one line at a time
  my @matches = $content =~ m/myPlayer\.Genre\('.*?',.*?<\/a>/sg;
  # Go through each of those matches extracting the bits we care about.
  # This is extra ugly due to greedy matching across multiple lines.
  foreach my $match (@matches) {
    if ($match =~
        m/myPlayer\.Genre\('.*?', '(\w+?)',.*?>\s*?([^\n\t]+?)\s*?<\/a>/s) {
      $genres{$1} = decode_entities($2);
    }
  }

  if (%genres) {
    $self->{error} = undef;
  } else {
    $self->_error("No genres found. Logged in?");
    $self->{loggedIn} = 0;
  }

  return %genres
}

# Extract channels from the HTML
sub _parseChannels {
  my $self = shift;
  my $content = shift;
  my %channels = ();

  foreach my $line (split(/\r?\n/, $content)) {
    if ($line =~ /Channel\('(.+)', '(.+)', '(.+?)',.*class="channel">(\d+)/) {
      $channels{$3}->{category} = $1;
      $channels{$3}->{genre} = $2;
      _debug("Channel: $3");
      $channels{$3}->{key} = $3;
      _debug("  Number: $4");
      $channels{$3}->{number} = $4;
    } elsif ($line =~ /Channel\('.+', '.+', '(.+?)',.*class="text">(.+)</) {
      $channels{$1}->{name} = decode_entities($2);
      _debug("  Name: $2");
    } elsif ($line =~ /Channel\('.+', '.+', '(.+?)',.*class="desc">(.+)</) {
      $channels{$1}->{desc} = decode_entities($2);
      _debug("  Desc: $2");
    }
  }

  if (%channels) {
    $self->{error} = undef;
  } else {
    $self->_error("No channels found. Logged in?");
    $self->{loggedIn} = 0;
  }

  return %channels
}

# Extract the stream URL from the HTML
sub _parseStream {
  my $self = shift;
  my $content = shift;
  my $stream;

  foreach my $line (split(/\r?\n/, $content)) {
    if ($line =~ /PARAM name="FileName" value="(.+)"/i) {
      $stream = $1;
    } elsif ($line =~ /Sorry_Pg3\.gif/) {
      $self->_error("Too many logins?");
    }
  }

  if ($stream) {
    $self->{error} = undef;
  } else {
    $self->_error("No stream found. Logged in?");
    $self->{loggedIn} = 0;
  }

  return $stream;
}

1;
