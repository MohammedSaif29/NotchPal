// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

#ifndef NOTCHPAL_MEDIA_BRIDGE_H
#define NOTCHPAL_MEDIA_BRIDGE_H

/// Entry point called by Support/media-bridge.pl through Perl's DynaLoader.
/// Perl passes its interpreter and the CV as arguments; the bridge ignores both.
/// Never returns: it streams Now Playing updates as JSON lines on stdout and
/// reads commands ("cmd <n>", "seek <seconds>") from stdin until stdin closes.
void notchpal_bridge_run(void *interpreter, void *cv);

#endif
