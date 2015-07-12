## Overview ##
SqueezeCenter plugin for listening to Sirius Internet Radio streams.  The official Sirius plugin provided by Logitech is US only and requires a premium subscription.  This plugin works for Sirius Canada as well as for those that still have access to the "free" low bandwidth streams.

## News ##
### 02/14/2011 - Version 1.1 ###
  * Fixed problems as a result of Sirius site redesign.

It's quite likely this fix isn't going to last long.  The real fix is unfortunately far more complicated due to the player being converted to flash and using RTMPE.  We'll cross that bridge when we come to it.

### 02/07/2011 - Well crap ###
It seems Sirius updated the player on the US site, so until I get a chance to fix it the plugin is officially broken.  Sirius Canada is still using the old player, so there shouldn't be any problems there.

### 06/26/2010 - Version 1.0 ###
  * Fixed bitrate handling issue for US streams
  * Added updated channel image
  * Major version bump to 1.0 since there are no outstanding issues that I'm aware of

### 03/05/2010 - Version 0.3 ###
  * Fixed long standing issue with some players (I hope).
  * Added updated channel images

### 01/31/2010 - Version 0.2 ###
  * Sirius finally stopped sending passwords in the clear on the US site.  Some debugging fixes, and the extension downloader should work better now.

### 11/20/2009 - It lives! ###
  * In an effort to prove that I was actually trying to solve this problem, I've released the first version of the plugin.  Please report any issues you may have.

## FAQ (sorta) ##
### Why another Sirius plugin? ###
  * The official Sirius plugin requires a premium subscription.
  * The official Sirius plugin is US only.
  * The official Sirius plugin doesn't allow you to stream different channels to multiple devices.
  * Greg Brown's [SiriusRadio](http://gregbrown.net/squeeze/sirius.htm) plugin appears to be abandoned, and it was easier to write a new basic OPML based plugin, then fix this one up (though I tried).
  * I wanted to base the plugin on a generic Sirius PERL module that could be used elsewhere.

### The Good ###
  * It works (for now)
  * It works on Squeezebox server versions 7.0a - 7.5.

### The Bad ###
  * It's not as feature rich as the original SiriusRadio plugin.
  * The first time you access the plugin it will be slow as all of the channel data is downloaded at once.
  * Sirius seems to be changing a lot of stuff right now on their site so it's a moving target.

### The Ugly ###
  * I threw this together pretty quickly.  It doesn't have very good error handling and isn't all the tolerant of upstream problems.

## Installation ##
Make sure you disable or uninstall the official Sirius plugin due to potential conflicts with how the sirius:// handler is used.

### Manual Installation ###
  * Remove any previous version of the plugin from the SqueezeCenter Plugins directory.
  * Download the latest version of the plugin from the [Downloads](http://code.google.com/p/notsosirius-squeezecenter/downloads/list) page.
  * Unzip the plugin into the Plugins directory.
  * Restart SqueezeCenter
  * Configure the plugin

### Using the Extension Downloader ###
  * Open up the Extension Downloader configuration in SqueezeCenter under Settings/Plugins/Extension Downloader/Settings
  * Add the repository:
> http://notsosirius-squeezecenter.googlecode.com/svn/tags/repo.xml
  * Select the plugin for installation
  * Restart SqueezeCenter
  * Configure the plugin

## Bugs and Known Issues ##
### Squeezebox Server 7.4 ###
You may encounter broken images due to some dumb behavior on Logitech's part in regards to how images are displayed and resized on the various frontends.

## Donate ##
Donations to the cause graciously accepted via PayPal:
[![](https://www.paypal.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=48NRH82ZKVGBA&lc=US&item_name=Robert%20Flemming&currency_code=USD&bn=PP%2dDonationsBF%3abtn_donate_SM%2egif%3aNonHosted)