package Plugins::NotSoSirius::Settings;

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

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use base qw(Slim::Web::Settings);

my $prefs = preferences('plugin.notsosirius');
my $log   = logger('plugin.notsosirius');

# Reload the plugin in the event any of the preferences have changed
$prefs->setChange(
  sub {
    my $newval = $_[1];

    if ($newval) {
      if ($log->is_debug) {
        $log->debug('Reloading plugin after config change');
      }
      Plugins::NotSoSirius::Plugin->initPlugin();
    }

    for my $c (Slim::Player::Client::clients()) {
      Slim::Buttons::Home::updateMenu($c);
    }
  }, 'account',
);

sub name {
  return 'PLUGIN_NOTSOSIRIUS';
}

sub page {
  return 'plugins/NotSoSirius/settings/basic.html';
}

sub handler {
  my ($class, $client, $params) = @_;

  if ($params->{saveSettings}) {
    push my @account, {
      username => $params->{pref_username} || '',
      password => $params->{pref_password} || '',
      country => $params->{pref_country} || 'US',
      bitrate => $params->{pref_bitrate} || 'high',
      type => $params->{pref_type} || 'subscriber'
    };
    $prefs->set('account', \@account);
  }

  # No support for multiple accounts, so just use the first one.
  my $accountRef = $prefs->get('account') || '';
  if ($accountRef) {
    $params->{prefs} = @{$accountRef}[0];
  } else {
    $params->{prefs} = {};
  }

  return $class->SUPER::handler($client, $params);
}

1;
