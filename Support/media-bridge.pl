#!/usr/bin/perl
# NotchPal, the notch that's alive.
# Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
# SPDX-License-Identifier: GPL-3.0-only
# Starts NotchPal's media bridge inside /usr/bin/perl.
# macOS only lets Apple's own programs read Now Playing info, and perl is one of them.
# Usage: /usr/bin/perl media-bridge.pl /path/to/libNotchPalMediaBridge.dylib
use strict;
use warnings;
use DynaLoader;

my $library = shift @ARGV or die "usage: media-bridge.pl <library>\n";
my $handle = DynaLoader::dl_load_file($library, 0)
    or die "could not load $library: " . DynaLoader::dl_error() . "\n";
my $symbol = DynaLoader::dl_find_symbol($handle, "notchpal_bridge_run")
    or die "notchpal_bridge_run not found in $library\n";
my $run = DynaLoader::dl_install_xsub("main::notchpal_bridge_run", $symbol);
&$run();
