// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

// NotchPal media bridge.
//
// Since macOS 15.4, only Apple-signed programs may read the system's Now Playing
// information. /usr/bin/perl is one of them, so NotchPal starts perl, perl loads
// this small library, and this library talks to the private MediaRemote framework.
//
// Output: one JSON object per line on stdout.
//   {"type":"ready"}
//   {"type":"none"}                                  nothing is playing
//   {"type":"info", "title":..., "artist":..., "album":..., "duration":...,
//    "elapsed":..., "timestamp":..., "rate":..., "playing":..., "pid":...,
//    "artwork": "<base64>" | ""}                     artwork only when it changes
//   {"type":"error", "message":...}
//
// Input: one command per line on stdin.
//   cmd <n>        MediaRemote command (2 = play/pause, 4 = next, 5 = previous)
//   seek <seconds>
// When stdin closes (NotchPal quit), the bridge exits.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <errno.h>
#import <string.h>
#import <unistd.h>

#import "NotchPalMediaBridge.h"

typedef void (*NPGetInfoFn)(dispatch_queue_t queue, void (^handler)(CFDictionaryRef info));
typedef void (*NPRegisterFn)(dispatch_queue_t queue);
typedef void (*NPGetIsPlayingFn)(dispatch_queue_t queue, void (^handler)(Boolean playing));
typedef void (*NPGetPIDFn)(dispatch_queue_t queue, void (^handler)(int pid));
typedef Boolean (*NPSendCommandFn)(int command, CFDictionaryRef options);
typedef void (*NPSetElapsedFn)(double seconds);

static NPGetInfoFn npGetInfo;
static NPRegisterFn npRegister;
static NPGetIsPlayingFn npGetIsPlaying;
static NPGetPIDFn npGetPID;
static NPSendCommandFn npSendCommand;
static NPSetElapsedFn npSetElapsed;

static NSData *npLastArtwork;
static NSString *npLastTrackKey;
static NSString *npLastSignature;
static BOOL npRefreshQueued;
static dispatch_source_t npInputSource;
static NSMutableData *npInputBuffer;

#pragma mark - Output

static void npEmit(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
    if (json == nil) {
        return;
    }
    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];

    const uint8_t *bytes = line.bytes;
    size_t remaining = line.length;
    while (remaining > 0) {
        ssize_t written = write(STDOUT_FILENO, bytes, remaining);
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written <= 0) {
            exit(0); // NotchPal went away.
        }
        bytes += written;
        remaining -= (size_t)written;
    }
}

static NSString *npString(id value) {
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

static double npDouble(id value, double fallback) {
    return [value isKindOfClass:[NSNumber class]] ? [(NSNumber *)value doubleValue] : fallback;
}

#pragma mark - Now Playing

static void npPublish(NSDictionary *info, BOOL playing, int pid) {
    NSString *title = npString(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
    if (info == nil || title.length == 0) {
        if (![npLastSignature isEqualToString:@"none"]) {
            npLastSignature = @"none";
            npLastTrackKey = nil;
            npLastArtwork = nil;
            npEmit(@{ @"type": @"none" });
        }
        return;
    }

    NSString *artist = npString(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
    NSString *album = npString(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
    double duration = npDouble(info[@"kMRMediaRemoteNowPlayingInfoDuration"], 0);
    double elapsed = npDouble(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"], 0);
    double rate = npDouble(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"], playing ? 1 : 0);
    id stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    double timestamp = [stamp isKindOfClass:[NSDate class]]
        ? [(NSDate *)stamp timeIntervalSince1970]
        : [[NSDate date] timeIntervalSince1970];

    NSMutableDictionary *message = [@{
        @"type": @"info",
        @"title": title,
        @"artist": artist,
        @"album": album,
        @"duration": @(duration),
        @"elapsed": @(elapsed),
        @"timestamp": @(timestamp),
        @"rate": @(rate),
        @"playing": @(playing),
        @"pid": @(pid),
    } mutableCopy];

    // Artwork is big, so only send it when it changes. Some apps drop the
    // artwork for a moment mid-song; keep the old one unless the song changed.
    NSString *trackKey = [NSString stringWithFormat:@"%@\n%@\n%@", title, artist, album];
    BOOL trackChanged = ![trackKey isEqualToString:npLastTrackKey];
    id artworkValue = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    NSData *artwork = [artworkValue isKindOfClass:[NSData class]] ? (NSData *)artworkValue : nil;
    BOOL sendsArtwork = NO;
    if (artwork.length > 0 && ![artwork isEqualToData:npLastArtwork]) {
        message[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
        npLastArtwork = artwork;
        sendsArtwork = YES;
    } else if (artwork.length == 0 && trackChanged) {
        message[@"artwork"] = @"";
        npLastArtwork = nil;
        sendsArtwork = YES;
    }
    npLastTrackKey = trackKey;

    NSString *signature = [NSString stringWithFormat:@"%@|%.2f|%.2f|%.3f|%.2f|%d|%d",
                           trackKey, duration, elapsed, timestamp, rate, playing, pid];
    if (!sendsArtwork && [signature isEqualToString:npLastSignature]) {
        return;
    }
    npLastSignature = signature;
    npEmit(message);
}

static void npRefresh(void) {
    npRefreshQueued = NO;
    dispatch_queue_t main = dispatch_get_main_queue();
    npGetInfo(main, ^(CFDictionaryRef cfInfo) {
        NSDictionary *info = cfInfo != NULL ? [(__bridge NSDictionary *)cfInfo copy] : nil;
        npGetIsPlaying(main, ^(Boolean playing) {
            if (npGetPID == NULL) {
                npPublish(info, playing, 0);
                return;
            }
            npGetPID(main, ^(int pid) {
                npPublish(info, playing, pid);
            });
        });
    });
}

static void npQueueRefresh(void) {
    if (npRefreshQueued) {
        return;
    }
    npRefreshQueued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        npRefresh();
    });
}

#pragma mark - Input

static void npHandleCommand(NSString *rawLine) {
    NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *verb = parts.firstObject;
    if ([verb isEqualToString:@"cmd"] && parts.count > 1 && npSendCommand != NULL) {
        npSendCommand(parts[1].intValue, NULL);
    } else if ([verb isEqualToString:@"seek"] && parts.count > 1 && npSetElapsed != NULL) {
        npSetElapsed(parts[1].doubleValue);
    }
    npQueueRefresh();
}

static void npStartInput(void) {
    npInputBuffer = [NSMutableData data];
    npInputSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(npInputSource, ^{
        char chunk[1024];
        ssize_t count = read(STDIN_FILENO, chunk, sizeof(chunk));
        if (count == 0) {
            exit(0); // NotchPal quit, so stop too.
        }
        if (count < 0) {
            if (errno == EINTR || errno == EAGAIN) {
                return;
            }
            exit(0);
        }
        [npInputBuffer appendBytes:chunk length:(NSUInteger)count];
        while (YES) {
            const char *bytes = npInputBuffer.bytes;
            const char *newline = memchr(bytes, '\n', npInputBuffer.length);
            if (newline == NULL) {
                break;
            }
            NSUInteger length = (NSUInteger)(newline - bytes);
            NSString *line = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
            [npInputBuffer replaceBytesInRange:NSMakeRange(0, length + 1) withBytes:NULL length:0];
            if (line != nil) {
                npHandleCommand(line);
            }
        }
    });
    dispatch_resume(npInputSource);
}

#pragma mark - Entry point

void notchpal_bridge_run(void *interpreter, void *cv) {
    (void)interpreter;
    (void)cv;

    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (handle == NULL) {
            npEmit(@{ @"type": @"error", @"message": @"MediaRemote is not available" });
            exit(2);
        }
        npGetInfo = (NPGetInfoFn)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        npRegister = (NPRegisterFn)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
        npGetIsPlaying = (NPGetIsPlayingFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        npGetPID = (NPGetPIDFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID");
        npSendCommand = (NPSendCommandFn)dlsym(handle, "MRMediaRemoteSendCommand");
        npSetElapsed = (NPSetElapsedFn)dlsym(handle, "MRMediaRemoteSetElapsedTime");

        if (npGetInfo == NULL || npRegister == NULL || npGetIsPlaying == NULL) {
            npEmit(@{ @"type": @"error", @"message": @"MediaRemote functions are missing" });
            exit(3);
        }

        npRegister(dispatch_get_main_queue());
        NSArray<NSString *> *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *note) {
                (void)note;
                npQueueRefresh();
            }];
        }

        npStartInput();
        npEmit(@{ @"type": @"ready" });
        npRefresh();

        // A slow safety net in case a player forgets to announce a change.
        // It also keeps the run loop alive.
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            npQueueRefresh();
        }];
    }

    CFRunLoopRun();
    exit(0);
}
