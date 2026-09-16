/// The address on the local network a phone can reach this machine at, and
/// the block `dartvel dev` prints for it.
library dartvel_cli.utils.lan_address;

import 'dart:io';

import 'qr_code.dart';

/// An address and the interface it belongs to.
///
/// The interface name is the part that matters: `docker0` holds a private
/// address on every Linux machine with Docker, is listed before the Wi-Fi, and
/// is unreachable from a phone. An address alone cannot tell the two apart.
class DVNamedAddress {
  const DVNamedAddress(this.interface, this.address);
  final String interface;
  final InternetAddress address;
}

/// Interfaces that belong to containers, virtual machines, VPNs or Apple's
/// peer-to-peer links rather than to the network a phone is on.
final RegExp _virtual = RegExp(
  r'^(docker|br-|veth|virbr|vmnet|vboxnet|lxc|lxdbr|cni|flannel|kube|podman|'
  r'tun|tap|utun|wg|tailscale|zt|awdl|llw|bridge|ipsec|ppp|gif|stf|anpi)',
);

/// The IPv4 host a phone on the same network should be given.
///
/// A private address on a physical interface first. Then a private address
/// on a virtual one, then any other routable address, and loopback only when
/// there is nothing else -- a URL that cannot work is still better printed
/// than nothing, and [dvLanPreviewUrl] refuses to announce it.
String dvLanHost(List<DVNamedAddress> addresses) {
  int rank(DVNamedAddress a) {
    final InternetAddress address = a.address;
    if (address.type != InternetAddressType.IPv4) return 99;
    if (address.isLoopback) return 9;
    if (address.isLinkLocal) return 8;
    final bool virtual = _virtual.hasMatch(a.interface.toLowerCase());
    final bool private = _isPrivate(address);
    if (private && !virtual) return 0;
    if (private) return 1;
    if (!virtual) return 2;
    return 3;
  }

  DVNamedAddress? best;
  for (final DVNamedAddress a in addresses) {
    if (rank(a) >= 99) continue;
    if (best == null || rank(a) < rank(best)) best = a;
  }
  return best?.address.address ?? InternetAddress.loopbackIPv4.address;
}

/// [dvLanHost] for this machine.
Future<String> dvDetectLanHost() async {
  try {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      includeLoopback: true,
      type: InternetAddressType.IPv4,
    );
    return dvLanHost(<DVNamedAddress>[
      for (final NetworkInterface i in interfaces)
        for (final InternetAddress a in i.addresses) DVNamedAddress(i.name, a),
    ]);
  } on Object {
    return InternetAddress.loopbackIPv4.address;
  }
}

bool _isPrivate(InternetAddress a) {
  final List<int> b = a.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

bool _isLoopbackName(String host) {
  final String h = host.toLowerCase();
  if (h == 'localhost') return true;
  final InternetAddress? parsed = InternetAddress.tryParse(h);
  return parsed != null && parsed.isLoopback;
}

/// The URL a phone opens for a server bound to [bindHost] on [port], or null
/// when no phone could reach it.
///
/// A server bound to every interface is announced at [lanHost]; one bound to
/// a specific address is announced there; one bound to loopback has no
/// address anything else can use, and neither does a machine whose best
/// address is loopback.
Uri? dvLanPreviewUrl({
  required String bindHost,
  required int port,
  required String lanHost,
}) {
  final String host;
  if (bindHost == '0.0.0.0' || bindHost == '::' || bindHost.isEmpty) {
    host = lanHost;
  } else {
    host = bindHost;
  }
  if (_isLoopbackName(host)) return null;
  return Uri(scheme: 'http', host: host, port: port);
}

/// A heading, a QR code of [link], and the link itself, as lines to print.
///
/// The link is printed as well as encoded: a camera that will not focus on a
/// terminal is common, and the text is what gets typed in instead.
List<String> dvQrBlock({
  required String heading,
  required String link,
  required bool ansi,
}) => <String>[
  heading,
  ...dvQrTerminalLines(DVQrCode.encodeText(link), ansi: ansi),
  '  $link',
];
