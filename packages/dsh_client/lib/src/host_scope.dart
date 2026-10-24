import 'dart:io';

/// Where a host address sits on the network, for deciding whether plain HTTP
/// is acceptable (loopback and private networks only).
enum HostScope {
  /// `localhost`, `127.0.0.0/8`, `::1`.
  loopback,

  /// RFC 1918, link-local, unique-local IPv6, and the shared address space
  /// `100.64.0.0/10` that Tailscale and carrier-grade NAT use.
  privateNetwork,

  /// Any other IP literal: reachable from the internet.
  public,

  /// A name, not an address. Whether it is private depends on what it
  /// resolves to ([classifyAddresses]); a name that clearly belongs to a local
  /// network (`.local`, `.lan`, a single label) is [privateNetwork] outright.
  name,
}

/// Classify the host part of a URL (no brackets around IPv6).
HostScope classifyHost(String host) {
  final lower = host.toLowerCase();
  final address = InternetAddress.tryParse(lower);
  if (address != null) return classifyAddress(address);
  if (lower == 'localhost' || lower.endsWith('.localhost')) {
    return HostScope.loopback;
  }
  if (!lower.contains('.') ||
      lower.endsWith('.local') ||
      lower.endsWith('.lan') ||
      lower.endsWith('.home.arpa') ||
      lower.endsWith('.internal')) {
    return HostScope.privateNetwork;
  }
  return HostScope.name;
}

/// Classify one resolved or literal address.
HostScope classifyAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv6) {
    // IPv4-mapped (::ffff:a.b.c.d) takes the scope of the embedded address.
    final mapped =
        bytes.sublist(0, 10).every((b) => b == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    if (mapped) return _v4(bytes.sublist(12));
    if (address.isLoopback) return HostScope.loopback;
    final first = bytes[0];
    // fc00::/7 unique local, fe80::/10 link local.
    if ((first & 0xfe) == 0xfc ||
        (first == 0xfe && (bytes[1] & 0xc0) == 0x80)) {
      return HostScope.privateNetwork;
    }
    return HostScope.public;
  }
  return _v4(bytes);
}

HostScope _v4(List<int> b) {
  if (b[0] == 127) return HostScope.loopback;
  if (b[0] == 10) return HostScope.privateNetwork;
  if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return HostScope.privateNetwork;
  if (b[0] == 192 && b[1] == 168) return HostScope.privateNetwork;
  if (b[0] == 169 && b[1] == 254) return HostScope.privateNetwork;
  if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return HostScope.privateNetwork;
  return HostScope.public;
}

/// The scope of a name from what it resolved to: private only when every
/// address is loopback or private, public as soon as one is public.
HostScope classifyAddresses(Iterable<InternetAddress> addresses) {
  var scope = HostScope.loopback;
  var any = false;
  for (final a in addresses) {
    any = true;
    switch (classifyAddress(a)) {
      case HostScope.public || HostScope.name:
        return HostScope.public;
      case HostScope.privateNetwork:
        scope = HostScope.privateNetwork;
      case HostScope.loopback:
        break;
    }
  }
  return any ? scope : HostScope.public;
}
