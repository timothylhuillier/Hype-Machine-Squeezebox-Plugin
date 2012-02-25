package Plugins::HypeM::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

sub name {
	return 'PLUGIN_HYPEM';
}

sub page {
	return 'plugins/HypeM/settings/basic.html';
}

sub prefs {
	return (preferences('plugin.hypem'), qw(username password token));
}

1;
