/// What `dartvel build ios|macos --profile development` writes so the build
/// pairs with `dartvel dev` and hot reloads over the network.
///
/// The same design as Android's (see android_dev_client.dart): the device
/// dials out to the dev server, over TLS pinned to the key in the pairing
/// link, and the dev server reaches the app's Dart VM service back through the
/// connection so `flutter attach` can reload it. The tunnel is native -- here
/// Objective-C on Network.framework, on threads of its own -- because a hot
/// restart kills every Dart isolate and the restart travels over the tunnel.
///
/// Three things go into the Xcode project, and all three are Debug-only:
///
///  * `Runner/DartvelDevClient.m`, compiled into the application, whose whole
///    body sits under `#if DEBUG`, so a Profile or Release configuration
///    compiles an empty file;
///  * `Runner/Info-Development.plist`, the application's own Info.plist with
///    the `dartvel-dev` URL scheme added, which only the Debug configuration
///    is pointed at -- a scheme in the Info.plist every configuration shares
///    would be a release build answering pairing links;
///  * on macOS, `Runner/DebugDevelopment.entitlements`, the Debug
///    entitlements with outgoing network connections allowed, which the
///    sandbox otherwise refuses.
///
/// Every object added to `project.pbxproj` carries [_idPrefix], and every
/// setting changed carries a `dartvel.devclient` comment, so a profile or release build takes all of
/// it back out and leaves the project byte for byte as it was.
library dartvel_cli.devclient.apple_dev_client;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart'
    show
        DVDevClientManifest,
        dvDevClientLinkScheme,
        dvDevClientShellMarker,
        dvDevClientTunnelPath,
        dvDevClientTunnelProtocol,
        dvIosLaunchUrlKey;

/// The tunnel's file name, under `ios/Runner` or `macos/Runner`.
const String dvAppleDevTunnelFile = 'DartvelDevClient.m';

/// The Info.plist the Debug configuration builds with, relative to the
/// platform directory.
const String dvAppleDevelopmentInfoPlistPath = 'Runner/Info-Development.plist';

/// The entitlements a macOS Debug configuration signs with.
const String dvMacosDevelopmentEntitlementsPath =
    'Runner/DebugDevelopment.entitlements';

/// The C function Dart hands its VM service URI to.
const String dvAppleDevClientVmServiceSymbol = 'dartvel_dev_client_vm_service';

/// The C function Dart asks for the dev server's host.
const String dvAppleDevClientServerHostSymbol =
    'dartvel_dev_client_server_host';

/// Not a hash of anything: one tunnel per project, so fixed ids are
/// deterministic, and 24 hexadecimal characters like Xcode's own.
const String _idPrefix = 'DA7DE0C11E';
const String _fileRefId = '${_idPrefix}00000000000001';
const String _buildFileId = '${_idPrefix}00000000000002';

// -- the Xcode project --------------------------------------------------------

/// [pbxproj] with the tunnel compiled into the application and its Debug
/// configuration pointed at the development Info.plist -- or, when not
/// [enabled], with all of that taken back out.
String dvApplePbxprojWithDevClient(String pbxproj, {required bool enabled}) {
  final String stripped = _strip(pbxproj);
  if (!enabled) return stripped;

  final String? target = _applicationTarget(stripped);
  if (target == null) return stripped;

  String out = stripped;
  out = _beforeSectionEnd(out, 'PBXBuildFile', <String>[
    '\t\t$_buildFileId /* $dvAppleDevTunnelFile in Sources */ = '
        '{isa = PBXBuildFile; fileRef = $_fileRefId /* $dvAppleDevTunnelFile */; };',
  ]);
  out = _beforeSectionEnd(out, 'PBXFileReference', <String>[
    '\t\t$_fileRefId /* $dvAppleDevTunnelFile */ = {isa = PBXFileReference; '
        'lastKnownFileType = sourcecode.c.objc; path = $dvAppleDevTunnelFile; '
        'sourceTree = "<group>"; };',
  ]);

  // Into the group that holds the application's AppDelegate.swift, which is
  // the Runner directory the file is written into.
  final String? group = _groupHolding(out, 'AppDelegate.swift');
  if (group != null) {
    out = _intoList(
      out,
      group,
      'children',
      '\t\t\t\t$_fileRefId /* $dvAppleDevTunnelFile */,',
    );
  }
  final String? sources = _sourcesPhase(out, target);
  if (sources != null) {
    out = _intoList(
      out,
      sources,
      'files',
      '\t\t\t\t$_buildFileId /* $dvAppleDevTunnelFile in Sources */,',
    );
  }

  final String? debug = _configuration(out, target, 'Debug');
  if (debug != null) {
    out = _replaceSetting(
      out,
      debug,
      'INFOPLIST_FILE',
      '"$dvAppleDevelopmentInfoPlistPath"',
    );
    out = _replaceSetting(
      out,
      debug,
      'CODE_SIGN_ENTITLEMENTS',
      '"$dvMacosDevelopmentEntitlementsPath"',
    );
  }
  return out;
}

String _strip(String pbxproj) {
  final List<String> kept = <String>[];
  for (final String line in pbxproj.split('\n')) {
    if (line.contains(_idPrefix)) continue;
    if (line.contains('/* dartvel.devclient ')) {
      // `\t\t\t\tNAME = "new"; /* dartvel.devclient Runner/Info.plist */`
      final RegExpMatch? m = RegExp(
        r'^(\s*)([A-Z_]+) = [^;]*; /\* dartvel\.devclient (.*) \*/$',
      ).firstMatch(line);
      if (m != null) {
        kept.add('${m.group(1)}${m.group(2)} = ${m.group(3)};');
        continue;
      }
    }
    kept.add(line);
  }
  return kept.join('\n');
}

/// The application's PBXNativeTarget, by its product type.
String? _applicationTarget(String pbxproj) {
  final RegExp target = RegExp(
    r'\t\t([0-9A-F]{24}) /\*[^*]*\*/ = \{\n\t\t\tisa = PBXNativeTarget;'
    r'.*?\n\t\t\};',
    dotAll: true,
  );
  for (final RegExpMatch match in target.allMatches(pbxproj)) {
    if (match.group(0)!.contains('"com.apple.product-type.application"')) {
      return match.group(1);
    }
  }
  return null;
}

/// The body of the object [id], from its opening line to its closing brace.
({int start, int end})? _object(String pbxproj, String id) {
  final RegExpMatch? open = RegExp(
    '^\\t\\t$id (?:/\\*[^*]*\\*/ )?= \\{\$',
    multiLine: true,
  ).firstMatch(pbxproj);
  if (open == null) return null;
  final int end = pbxproj.indexOf('\n\t\t};', open.end);
  if (end < 0) return null;
  return (start: open.start, end: end);
}

String? _groupHolding(String pbxproj, String child) {
  final RegExp group = RegExp(
    r'\t\t([0-9A-F]{24}) (?:/\*[^*]*\*/ )?= \{\n\t\t\tisa = PBXGroup;.*?\n\t\t\};',
    dotAll: true,
  );
  for (final RegExpMatch match in group.allMatches(pbxproj)) {
    if (match.group(0)!.contains('/* $child */,')) return match.group(1);
  }
  return null;
}

String? _sourcesPhase(String pbxproj, String target) {
  final ({int start, int end})? object = _object(pbxproj, target);
  if (object == null) return null;
  return RegExp(
    r'([0-9A-F]{24}) /\* Sources \*/',
  ).firstMatch(pbxproj.substring(object.start, object.end))?.group(1);
}

String? _configuration(String pbxproj, String target, String name) {
  final ({int start, int end})? object = _object(pbxproj, target);
  if (object == null) return null;
  final String? list = RegExp(
    r'buildConfigurationList = ([0-9A-F]{24})',
  ).firstMatch(pbxproj.substring(object.start, object.end))?.group(1);
  if (list == null) return null;
  final ({int start, int end})? configurations = _object(pbxproj, list);
  if (configurations == null) return null;
  return RegExp('([0-9A-F]{24}) /\\* $name \\*/')
      .firstMatch(pbxproj.substring(configurations.start, configurations.end))
      ?.group(1);
}

/// [line] as the last entry of the list [key] inside the object [id].
String _intoList(String pbxproj, String id, String key, String line) {
  final ({int start, int end})? object = _object(pbxproj, id);
  if (object == null) return pbxproj;
  final int open = pbxproj.indexOf('\t\t\t$key = (\n', object.start);
  if (open < 0 || open > object.end) return pbxproj;
  final int close = pbxproj.indexOf('\n\t\t\t);', open);
  if (close < 0 || close > object.end) return pbxproj;
  return '${pbxproj.substring(0, close)}\n$line${pbxproj.substring(close)}';
}

/// The build setting [name] of configuration [id] set to [value], with its
/// old value kept in the marker so stripping restores it exactly. A
/// configuration without the setting is left without it.
String _replaceSetting(String pbxproj, String id, String name, String value) {
  final ({int start, int end})? object = _object(pbxproj, id);
  if (object == null) return pbxproj;
  final RegExp setting = RegExp('^(\\t+)$name = ([^;]*);\$', multiLine: true);
  final String body = pbxproj.substring(object.start, object.end);
  final RegExpMatch? m = setting.firstMatch(body);
  if (m == null) return pbxproj;
  // The old value rides in the comment: `NAME = new; /* dartvel.devclient
  // old */`, which is what stripping puts back.
  final String replaced =
      '${m.group(1)}$name = $value; /* dartvel.devclient ${m.group(2)} */';
  return pbxproj.substring(0, object.start) +
      body.replaceRange(m.start, m.end, replaced) +
      pbxproj.substring(object.end);
}

String _beforeSectionEnd(String pbxproj, String section, List<String> lines) {
  final String end = '/* End $section section */';
  final int at = pbxproj.indexOf(end);
  if (at < 0) return pbxproj;
  return '${pbxproj.substring(0, at)}${lines.join('\n')}\n'
      '${pbxproj.substring(at)}';
}

// -- the Info.plist and entitlements -----------------------------------------

const String _plistStart = '\t<!-- dartvel.devclient: begin -->';
const String _plistEnd = '\t<!-- dartvel.devclient: end -->';

/// The development Info.plist: [info], the application's own, with the
/// `dartvel-dev` URL scheme -- added to a CFBundleURLTypes array the
/// application already declares, or as one of its own -- and a reason for
/// reaching the local network, which iOS asks the person holding the phone.
String dvAppleDevelopmentInfoPlist(String info) {
  // Written as whole lines ending in a newline, so taking the block out
  // restores the file exactly.
  final RegExp marked = RegExp(
    '${RegExp.escape(_plistStart)}.*?${RegExp.escape(_plistEnd)}\n',
    dotAll: true,
  );
  String out = info.replaceAll(marked, '');
  const String urlType =
      '\t\t<dict>\n'
      '\t\t\t<key>CFBundleURLName</key>\n'
      '\t\t\t<string>dev.dartvel.devclient</string>\n'
      '\t\t\t<key>CFBundleURLSchemes</key>\n'
      '\t\t\t<array>\n'
      '\t\t\t\t<string>$dvDevClientLinkScheme</string>\n'
      '\t\t\t</array>\n'
      '\t\t</dict>\n';
  final int types = out.indexOf('<key>CFBundleURLTypes</key>');
  if (types >= 0) {
    final int array = out.indexOf('<array>', types);
    final int line = out.indexOf('\n', array);
    out =
        '${out.substring(0, line + 1)}$_plistStart\n$urlType$_plistEnd\n'
        '${out.substring(line + 1)}';
  }
  final StringBuffer block = StringBuffer()..writeln(_plistStart);
  if (types < 0) {
    block
      ..writeln('\t<key>CFBundleURLTypes</key>')
      ..writeln('\t<array>')
      ..write(urlType)
      ..writeln('\t</array>');
  }
  if (!out.contains('<key>NSLocalNetworkUsageDescription</key>')) {
    block
      ..writeln('\t<key>NSLocalNetworkUsageDescription</key>')
      ..writeln(
        '\t<string>Pairs this development build with dartvel dev on your '
        'network.</string>',
      );
  }
  block.writeln(_plistEnd);
  final int close = out.lastIndexOf('</dict>');
  if (close < 0) return out;
  return '${out.substring(0, close)}$block${out.substring(close)}';
}

/// A macOS Debug configuration's entitlements with outgoing connections
/// allowed: [entitlements], the ones it was signed with, plus
/// `com.apple.security.network.client`, without which the sandbox refuses the
/// tunnel's connection to the dev server.
String dvMacosDevelopmentEntitlements(String entitlements) {
  if (entitlements.contains('com.apple.security.network.client')) {
    return entitlements;
  }
  final int close = entitlements.lastIndexOf('</dict>');
  if (close < 0) return entitlements;
  return '${entitlements.substring(0, close)}'
      '\t<key>com.apple.security.network.client</key>\n\t<true/>\n'
      '${entitlements.substring(close)}';
}

// -- the tunnel ---------------------------------------------------------------

String _objcString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// The Objective-C tunnel, recording [manifest] -- what this build compiled
/// in, which a hot restart can change in Dart but not natively.
String dvAppleDevTunnelSource(DVDevClientManifest manifest) {
  final String json = _objcString(jsonEncode(manifest.toJson()));
  return '''
// GENERATED by dartvel build --profile development. Do not edit.
//
// The native half of a development build's pairing with `dartvel dev`, for
// iOS and macOS. Dart calls dartvel_dev_client_vm_service() over FFI when the
// app starts, with the URI of its own Dart VM service. A pairing link arrives
// as a dartvel-dev:// URL (on iOS through the launch capture dartvel build
// writes into AppDelegate.swift, on macOS as an Apple Event) or as a launch
// argument. With both, the tunnel dials out to the dev server over TLS,
// trusting only a certificate for the key in the link, and the dev server
// reaches the VM service back through it. The tunnel runs on threads of its
// own, which a hot restart -- that kills every Dart isolate -- does not touch.
//
// Compiled only into a Debug configuration: everything below is inside
// #if DEBUG.

#if DEBUG

#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <Security/Security.h>
#include <string.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

static NSString *const DVPath = @"$dvDevClientTunnelPath";
static NSString *const DVProtocol = @"$dvDevClientTunnelProtocol";
static NSString *const DVScheme = @"$dvDevClientLinkScheme";
static NSString *const DVManifest = @"$json";
// Referenced so the build is recognisable as a development build.
static NSString *const DVMarker = @"$dvDevClientShellMarker";
static NSString *const DVLinkKey = @"dev.dartvel.devclient.link";
static NSString *const DVLaunchUrlKey = @"$dvIosLaunchUrlKey";

static NSObject *DVLock(void) {
  static NSObject *lock;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ lock = [NSObject new]; });
  return lock;
}

static NSString *DVStatus = @"not paired: scan the code dartvel dev prints";

static void DVSetStatus(NSString *status) {
  @synchronized (DVLock()) {
    DVStatus = [status copy];
  }
  NSLog(@"[DartvelDevClient] %@", status);
}

/// [candidate] when it is a pairing link, else nil.
static NSString *DVPairLink(NSString *candidate) {
  if (![candidate isKindOfClass:[NSString class]]) return nil;
  NSString *prefix = [DVScheme stringByAppendingString:@"://pair"];
  return [candidate hasPrefix:prefix] ? candidate : nil;
}

/// Whether [trust]'s leaf certificate carries [pin], an uncompressed P-256
/// point, as its public key. The key is read from the certificate's public
/// key info by Security, never searched for in its bytes.
static BOOL DVTrustHoldsKey(SecTrustRef trust, NSData *pin) {
  if (trust == NULL) return NO;
  SecCertificateRef leaf = NULL;
  if (@available(iOS 15.0, macOS 12.0, *)) {
    CFArrayRef chain = SecTrustCopyCertificateChain(trust);
    if (chain != NULL) {
      if (CFArrayGetCount(chain) > 0) {
        leaf = (SecCertificateRef)CFRetain(CFArrayGetValueAtIndex(chain, 0));
      }
      CFRelease(chain);
    }
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (SecTrustGetCertificateCount(trust) > 0) {
      leaf = (SecCertificateRef)CFRetain(SecTrustGetCertificateAtIndex(trust, 0));
    }
#pragma clang diagnostic pop
  }
  if (leaf == NULL) return NO;
  SecKeyRef key = SecCertificateCopyKey(leaf);
  CFRelease(leaf);
  if (key == NULL) return NO;
  CFDataRef point = SecKeyCopyExternalRepresentation(key, NULL);
  CFRelease(key);
  if (point == NULL) return NO;
  BOOL same = (NSUInteger)CFDataGetLength(point) == pin.length &&
      timingsafe_bcmp(CFDataGetBytePtr(point), pin.bytes, pin.length) == 0;
  CFRelease(point);
  return same;
}

static NSData *DVBase64UrlDecode(NSString *text) {
  NSMutableString *s = [[text stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
  [s replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, s.length)];
  while (s.length % 4 != 0) [s appendString:@"="];
  return [[NSData alloc] initWithBase64EncodedString:s options:0];
}

static NSString *DVBase64UrlEncode(NSData *data) {
  NSString *s = [data base64EncodedStringWithOptions:0];
  s = [s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
  s = [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  return [s stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

// -- a blocking connection over Network.framework ----------------------------

@interface DVDevConnection : NSObject
@property(nonatomic, readonly) BOOL pinRefused;
- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port pin:(NSData *)pin;
- (NSString *)open;
- (BOOL)write:(NSData *)data;
- (NSData *)read:(NSUInteger)max;
- (NSString *)readLine;
- (void)close;
@end

@implementation DVDevConnection {
  nw_connection_t _connection;
  dispatch_queue_t _queue;
  NSMutableData *_buffer;
  BOOL _eof;
  BOOL _pinRefused;
}

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port pin:(NSData *)pin {
  if ((self = [super init])) {
    _queue = dispatch_queue_create("dev.dartvel.devclient.connection", DISPATCH_QUEUE_SERIAL);
    _buffer = [NSMutableData data];
    NSString *service = [NSString stringWithFormat:@"%u", port];
    nw_endpoint_t endpoint = nw_endpoint_create_host(host.UTF8String, service.UTF8String);
    nw_parameters_t parameters;
    if (pin != nil) {
      __weak DVDevConnection *weakSelf = self;
      dispatch_queue_t queue = _queue;
      NSData *pinned = [pin copy];
      parameters = nw_parameters_create_secure_tcp(^(nw_protocol_options_t tls) {
        sec_protocol_options_t options = nw_tls_copy_sec_protocol_options(tls);
        sec_protocol_options_set_min_tls_protocol_version(options, tls_protocol_version_TLSv12);
        sec_protocol_options_set_verify_block(
            options,
            ^(sec_protocol_metadata_t metadata, sec_trust_t trust, sec_protocol_verify_complete_t complete) {
              SecTrustRef ref = sec_trust_copy_ref(trust);
              BOOL trusted = DVTrustHoldsKey(ref, pinned);
              if (ref != NULL) CFRelease(ref);
              if (!trusted) {
                DVDevConnection *strong = weakSelf;
                if (strong != nil) strong->_pinRefused = YES;
              }
              complete(trusted);
            },
            queue);
      }, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    } else {
      parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL,
                                                   NW_PARAMETERS_DEFAULT_CONFIGURATION);
    }
    _connection = nw_connection_create(endpoint, parameters);
    nw_connection_set_queue(_connection, _queue);
  }
  return self;
}

- (BOOL)pinRefused {
  return _pinRefused;
}

/// Nil once the connection is ready, else why it is not.
- (NSString *)open {
  dispatch_semaphore_t settled = dispatch_semaphore_create(0);
  __block BOOL ready = NO;
  __block BOOL done = NO;
  __block NSString *failure = nil;
  nw_connection_set_state_changed_handler(_connection, ^(nw_connection_state_t state, nw_error_t error) {
    if (done) return;
    if (state == nw_connection_state_ready) {
      ready = YES;
    } else if (state == nw_connection_state_failed || state == nw_connection_state_waiting ||
               state == nw_connection_state_cancelled) {
      failure = error != nil ? [NSString stringWithFormat:@"%@", error] : @"the connection failed";
    } else {
      return;
    }
    done = YES;
    dispatch_semaphore_signal(settled);
  });
  nw_connection_start(_connection);
  if (dispatch_semaphore_wait(settled, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0) {
    [self close];
    return @"timed out connecting";
  }
  if (!ready) {
    [self close];
    return failure ?: @"the connection failed";
  }
  return nil;
}

- (BOOL)write:(NSData *)data {
  if (_connection == nil) return NO;
  dispatch_semaphore_t sent = dispatch_semaphore_create(0);
  __block BOOL ok = NO;
  dispatch_data_t content = dispatch_data_create(data.bytes, data.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
  nw_connection_send(_connection, content, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, false, ^(nw_error_t error) {
    ok = error == nil;
    dispatch_semaphore_signal(sent);
  });
  dispatch_semaphore_wait(sent, DISPATCH_TIME_FOREVER);
  return ok;
}

/// Up to [max] bytes, or nil at the end of the stream.
- (NSData *)read:(NSUInteger)max {
  if (_buffer.length > 0) {
    NSUInteger n = MIN(max, _buffer.length);
    NSData *head = [_buffer subdataWithRange:NSMakeRange(0, n)];
    [_buffer replaceBytesInRange:NSMakeRange(0, n) withBytes:NULL length:0];
    return head;
  }
  if (_eof || _connection == nil) return nil;
  dispatch_semaphore_t arrived = dispatch_semaphore_create(0);
  __block NSMutableData *got = nil;
  __block BOOL end = NO;
  nw_connection_receive(_connection, 1, (uint32_t)max,
      ^(dispatch_data_t content, nw_content_context_t context, bool complete, nw_error_t error) {
        if (content != nil) {
          got = [NSMutableData data];
          dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *bytes, size_t size) {
            [got appendBytes:bytes length:size];
            return true;
          });
        }
        if (complete || error != nil) end = YES;
        dispatch_semaphore_signal(arrived);
      });
  dispatch_semaphore_wait(arrived, DISPATCH_TIME_FOREVER);
  if (end) _eof = YES;
  return got.length > 0 ? got : nil;
}

/// A line ending in \\n, without it or a \\r before it; nil at the end.
- (NSString *)readLine {
  while (YES) {
    const char *bytes = _buffer.bytes;
    for (NSUInteger i = 0; i < _buffer.length; i++) {
      if (bytes[i] != '\\n') continue;
      NSUInteger length = (i > 0 && bytes[i - 1] == '\\r') ? i - 1 : i;
      NSString *line = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
      [_buffer replaceBytesInRange:NSMakeRange(0, i + 1) withBytes:NULL length:0];
      return line ?: @"";
    }
    if (_buffer.length > 65536 || _eof || _connection == nil) return nil;
    dispatch_semaphore_t arrived = dispatch_semaphore_create(0);
    __block BOOL end = NO;
    NSMutableData *buffer = _buffer;
    nw_connection_receive(_connection, 1, 16384,
        ^(dispatch_data_t content, nw_content_context_t context, bool complete, nw_error_t error) {
          if (content != nil) {
            dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *b, size_t size) {
              [buffer appendBytes:b length:size];
              return true;
            });
          }
          if (complete || error != nil) end = YES;
          dispatch_semaphore_signal(arrived);
        });
    dispatch_semaphore_wait(arrived, DISPATCH_TIME_FOREVER);
    if (end) _eof = YES;
  }
}

- (void)close {
  nw_connection_t connection = _connection;
  _connection = nil;
  if (connection != nil) nw_connection_cancel(connection);
}

@end

// -- the tunnel --------------------------------------------------------------

@interface DVDevTunnel : NSObject
@property(nonatomic, readonly) NSString *host;
+ (instancetype)tunnelWithLink:(NSString *)link vmService:(NSString *)vmService error:(NSString **)error;
- (void)run;
- (void)close;
@end

@implementation DVDevTunnel {
  NSString *_host;
  uint16_t _port;
  NSString *_token;
  NSData *_key;
  uint16_t _vmPort;
  NSString *_vmPath;
  volatile BOOL _closed;
  DVDevConnection *_control;
}

+ (instancetype)tunnelWithLink:(NSString *)link vmService:(NSString *)vmService error:(NSString **)error {
  NSURLComponents *components = [NSURLComponents componentsWithString:link];
  if (components == nil || ![components.scheme isEqualToString:DVScheme]) {
    *error = [NSString stringWithFormat:@"not a %@ link", DVScheme];
    return nil;
  }
  NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
  for (NSURLQueryItem *item in components.queryItems) {
    if (item.value != nil) query[item.name] = item.value;
  }
  NSURL *server = query[@"server"] ? [NSURL URLWithString:query[@"server"]] : nil;
  NSData *key = query[@"key"] ? DVBase64UrlDecode(query[@"key"]) : nil;
  if (server == nil || query[@"token"] == nil || key == nil) {
    *error = @"the link names no server, token or key";
    return nil;
  }
  if (![server.scheme isEqualToString:@"https"]) {
    *error = @"the link names a dev server that is not https; scan the code a current dartvel dev prints";
    return nil;
  }
  const unsigned char *point = key.bytes;
  if (key.length != 65 || point[0] != 0x04) {
    *error = @"the link's key is not a P-256 point";
    return nil;
  }
  NSURL *vm = [NSURL URLWithString:vmService];
  if (vm == nil || vm.port == nil) {
    *error = @"the VM service URI has no port";
    return nil;
  }
  DVDevTunnel *tunnel = [DVDevTunnel new];
  tunnel->_host = server.host;
  tunnel->_port = server.port != nil ? server.port.unsignedShortValue : 443;
  tunnel->_token = query[@"token"];
  tunnel->_key = key;
  tunnel->_vmPort = vm.port.unsignedShortValue;
  tunnel->_vmPath = vm.path.length > 0 ? vm.path : @"/";
  if (![tunnel->_vmPath hasSuffix:@"/"]) tunnel->_vmPath = [tunnel->_vmPath stringByAppendingString:@"/"];
  return tunnel;
}

- (NSString *)host {
  return _host;
}

- (NSString *)server {
  return [NSString stringWithFormat:@"%@:%u", _host, _port];
}

- (void)close {
  _closed = YES;
  [_control close];
}

- (void)run {
  int attempt = 0;
  while (!_closed) {
    attempt++;
    DVSetStatus([NSString stringWithFormat:@"connecting to %@", [self server]]);
    NSString *refused = nil;
    NSString *failure = [self runControlRefused:&refused];
    if (_closed) return;
    if (refused != nil) {
      DVSetStatus(refused);
      return;
    }
    if (failure == nil) {
      DVSetStatus([NSString stringWithFormat:@"the dev server at %@ disconnected", [self server]]);
      attempt = 0;
    } else {
      DVSetStatus([NSString stringWithFormat:@"could not reach the dev server at %@: %@", [self server], failure]);
    }
    [NSThread sleepForTimeInterval:MAX(1.0, MIN(10.0, (double)attempt))];
  }
}

/// A tunnel connection that has been upgraded, or nil with [failure] or
/// [refused] set.
- (DVDevConnection *)open:(NSString *)query failure:(NSString **)failure refused:(NSString **)refused {
  uint8_t random[32];
  if (SecRandomCopyBytes(kSecRandomDefault, sizeof(random), random) != errSecSuccess) {
    *failure = @"no secure random bytes for the nonce";
    return nil;
  }
  NSString *nonce = DVBase64UrlEncode([NSData dataWithBytes:random length:sizeof(random)]);
  DVDevConnection *connection = [[DVDevConnection alloc] initWithHost:_host port:_port pin:_key];
  NSString *error = [connection open];
  if (error != nil) {
    if (connection.pinRefused) {
      *refused = [NSString stringWithFormat:@"the server at %@ did not present the key this device was "
                                            @"paired with, so nothing was sent to it.", [self server]];
    } else {
      *failure = error;
    }
    return nil;
  }
  NSString *request = [NSString stringWithFormat:
      @"GET %@?%@&nonce=%@ HTTP/1.1\\r\\nHost: %@\\r\\nAuthorization: Bearer %@\\r\\n"
      @"Connection: Upgrade\\r\\nUpgrade: %@\\r\\n\\r\\n",
      DVPath, query, nonce, [self server], _token, DVProtocol];
  if (![connection write:[request dataUsingEncoding:NSUTF8StringEncoding]]) {
    [connection close];
    *failure = @"the dev server closed the connection";
    return nil;
  }
  NSString *status = [connection readLine];
  NSString *line;
  while ((line = [connection readLine]) != nil && line.length > 0) {
  }
  NSArray<NSString *> *parts = [status componentsSeparatedByString:@" "];
  NSInteger code = parts.count > 1 ? parts[1].integerValue : 0;
  if (code == 401) {
    [connection close];
    *refused = [NSString stringWithFormat:@"the dev server at %@ refused this device. Its pairing ends "
                                          @"when dartvel dev restarts; scan the new code.", [self server]];
    return nil;
  }
  if (code != 101) {
    [connection close];
    *failure = [NSString stringWithFormat:@"the dev server answered HTTP %ld", (long)code];
    return nil;
  }
  return connection;
}

/// Nil when the control connection ended normally, else why it failed.
- (NSString *)runControlRefused:(NSString **)refused {
  NSString *failure = nil;
  DVDevConnection *control = [self open:@"role=control" failure:&failure refused:refused];
  if (control == nil) return failure;
  _control = control;
  NSString *hello = [NSString stringWithFormat:@"{\\"vmService\\":\\"%@\\",\\"manifest\\":%@}\\n", _vmPath, DVManifest];
  [control write:[hello dataUsingEncoding:NSUTF8StringEncoding]];
  DVSetStatus([NSString stringWithFormat:@"paired with %@", [self server]]);
  NSString *line;
  while ((line = [control readLine]) != nil) {
    if ([line hasPrefix:@"open "]) {
      NSString *identifier = [[line substringFromIndex:5] stringByTrimmingCharactersInSet:
          NSCharacterSet.whitespaceCharacterSet];
      [NSThread detachNewThreadWithBlock:^{
        [self stream:identifier];
      }];
    } else if ([line hasPrefix:@"refused "]) {
      *refused = [@"the dev server refused this build: " stringByAppendingString:[line substringFromIndex:8]];
      break;
    }
  }
  [control close];
  _control = nil;
  return nil;
}

- (void)stream:(NSString *)identifier {
  NSString *failure = nil;
  NSString *refused = nil;
  DVDevConnection *up = [self open:[@"role=stream&id=" stringByAppendingString:identifier]
                           failure:&failure refused:&refused];
  if (up == nil) {
    DVSetStatus([NSString stringWithFormat:@"a stream to the VM service failed: %@", failure ?: refused]);
    return;
  }
  DVDevConnection *vm = [[DVDevConnection alloc] initWithHost:@"127.0.0.1" port:_vmPort pin:nil];
  NSString *error = [vm open];
  if (error != nil) {
    DVSetStatus([NSString stringWithFormat:@"a stream to the VM service failed: %@", error]);
    [up close];
    return;
  }
  [NSThread detachNewThreadWithBlock:^{
    NSData *chunk;
    while ((chunk = [vm read:16384]) != nil) {
      if (![up write:chunk]) break;
    }
    [up close];
    [vm close];
  }];
  NSData *chunk;
  while ((chunk = [up read:16384]) != nil) {
    if (![vm write:chunk]) break;
  }
  [up close];
  [vm close];
}

@end

// -- pairing, and what Dart calls --------------------------------------------

static NSString *DVVmService;
static NSString *DVLink;
static DVDevTunnel *DVTunnel;

static void DVStart(void) {
  if (DVLink == nil || DVVmService == nil || DVTunnel != nil) return;
  NSString *error = nil;
  DVDevTunnel *tunnel = [DVDevTunnel tunnelWithLink:DVLink vmService:DVVmService error:&error];
  if (tunnel == nil) {
    DVSetStatus([@"the pairing link could not be used: " stringByAppendingString:error]);
    return;
  }
  DVTunnel = tunnel;
  [NSThread detachNewThreadWithBlock:^{
    [tunnel run];
  }];
}

static void DVPair(NSString *link) {
  @synchronized (DVLock()) {
    // Set before the defaults are written: writing them posts the change
    // notification, whose observer pairs only a link that differs from this.
    DVLink = [link copy];
    [NSUserDefaults.standardUserDefaults setObject:DVLink forKey:DVLinkKey];
    [DVTunnel close];
    DVTunnel = nil;
    DVStart();
  }
}

#if TARGET_OS_OSX
@interface DVDevURLEvents : NSObject
@end

@implementation DVDevURLEvents

+ (void)load {
  // Registered as the application finishes launching, which is late enough
  // that AppKit does not replace it and early enough to see a link the
  // application was launched with.
  [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillFinishLaunchingNotification
                                                  object:nil
                                                   queue:nil
                                              usingBlock:^(NSNotification *note) {
    static DVDevURLEvents *handler;
    handler = [DVDevURLEvents new];
    [NSAppleEventManager.sharedAppleEventManager setEventHandler:handler
                                                     andSelector:@selector(handle:reply:)
                                                   forEventClass:kInternetEventClass
                                                      andEventID:kAEGetURL];
  }];
}

- (void)handle:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply {
  NSString *text = [event paramDescriptorForKeyword:keyDirectObject].stringValue;
  NSString *link = DVPairLink(text);
  if (link != nil) {
    // Where iOS's launch capture puts a link too; the observer pairs.
    [NSUserDefaults.standardUserDefaults setObject:link forKey:DVLaunchUrlKey];
    return;
  }
  // Any other URL goes where it would have gone.
  NSURL *url = text != nil ? [NSURL URLWithString:text] : nil;
  id<NSApplicationDelegate> delegate = NSApp.delegate;
  if (url != nil && [delegate respondsToSelector:@selector(application:openURLs:)]) {
    [delegate application:NSApp openURLs:@[ url ]];
  }
}

@end
#endif

static void DVObserveLinks(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
                                                    object:nil
                                                     queue:nil
                                                usingBlock:^(NSNotification *note) {
      NSString *link = DVPairLink([NSUserDefaults.standardUserDefaults stringForKey:DVLaunchUrlKey]);
      @synchronized (DVLock()) {
        if (link != nil && DVVmService != nil && ![link isEqualToString:DVLink]) DVPair(link);
      }
    }];
  });
}

static char DVStatusBuffer[2048];
static char DVHostBuffer[512];

/// Called from Dart with this app's VM service URI. Returns the status, in a
/// buffer this file owns.
__attribute__((visibility("default"), used))
const char *$dvAppleDevClientVmServiceSymbol(const char *uri) {
  @autoreleasepool {
    @synchronized (DVLock()) {
      NSString *offered = uri != NULL ? [NSString stringWithUTF8String:uri] : nil;
      // The first URI this process reported: a restarted isolate can report
      // the dev machine's DDS address instead of this device's service.
      if (DVVmService == nil) DVVmService = offered;
      if (DVLink == nil) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSString *argument = nil;
        for (NSString *candidate in NSProcessInfo.processInfo.arguments) {
          if (DVPairLink(candidate) != nil) argument = candidate;
        }
        NSString *launched = DVPairLink([defaults stringForKey:DVLaunchUrlKey]);
        DVLink = argument ?: launched ?: DVPairLink([defaults stringForKey:DVLinkKey]);
        if (DVLink != nil) [defaults setObject:DVLink forKey:DVLinkKey];
      }
      DVObserveLinks();
      DVStart();
      strlcpy(DVStatusBuffer, (DVStatus ?: @"").UTF8String, sizeof(DVStatusBuffer));
      return DVMarker.length > 0 ? DVStatusBuffer : DVStatusBuffer;
    }
  }
}

/// The dev server's host, for reaching the backend it runs beside; NULL
/// before a tunnel starts.
__attribute__((visibility("default"), used))
const char *$dvAppleDevClientServerHostSymbol(void) {
  @synchronized (DVLock()) {
    if (DVTunnel == nil || DVTunnel.host == nil) return NULL;
    strlcpy(DVHostBuffer, DVTunnel.host.UTF8String, sizeof(DVHostBuffer));
    return DVHostBuffer;
  }
}

#endif
''';
}
