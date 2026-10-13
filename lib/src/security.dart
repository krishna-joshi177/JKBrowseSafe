import 'dart:convert';
import 'dart:math' as math;

/// Pure security helpers (no Flutter imports, so they are unit-tested).

// ---------------------------------------------------------------------------
// Domains
// ---------------------------------------------------------------------------

/// Common two-part public suffixes, so "sbi.co.in" is treated as one site.
const Set<String> _multiPartSuffixes = <String>{
  'co.in', 'org.in', 'net.in', 'gov.in', 'ac.in', 'edu.in', 'res.in',
  'firm.in', 'gen.in', 'ind.in', 'nic.in',
  'co.uk', 'org.uk', 'ac.uk', 'gov.uk',
  'com.au', 'net.au', 'org.au', 'co.nz', 'co.jp', 'co.kr', 'co.za',
  'com.br', 'com.cn', 'com.sg', 'com.my', 'com.pk', 'com.bd', 'com.np',
  'com.lk', 'com.tr', 'com.mx', 'com.ar', 'co.id', 'com.hk', 'com.tw',
};

final RegExp _hostRe = RegExp(
    r'^[a-z0-9]([a-z0-9_-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$');
final RegExp _ipv4Re = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

bool isIpAddress(String host) => _ipv4Re.hasMatch(host) || host.contains(':');

bool isValidHost(String host) =>
    host.length <= 253 && !isIpAddress(host) && _hostRe.hasMatch(host);

/// The part of a host name that identifies the real owner,
/// e.g. "login.paypal.com.evil.xyz" -> "evil.xyz".
String registrableDomain(String host) {
  final h = host.toLowerCase();
  if (h.isEmpty || isIpAddress(h)) return h;
  final p = h.split('.');
  if (p.length <= 2) return h;
  final lastTwo = '${p[p.length - 2]}.${p.last}';
  final keep = _multiPartSuffixes.contains(lastTwo) ? 3 : 2;
  if (p.length <= keep) return h;
  return p.sublist(p.length - keep).join('.');
}

/// True if [host] or any parent domain is in [set].
bool hostInSet(Set<String> set, String host) {
  if (set.isEmpty || host.isEmpty) return false;
  var h = host.toLowerCase();
  while (true) {
    if (set.contains(h)) return true;
    final i = h.indexOf('.');
    if (i < 0) return false;
    h = h.substring(i + 1);
  }
}

const List<String> _brands = <String>[
  'paypal', 'google', 'microsoft', 'apple', 'amazon', 'facebook',
  'instagram', 'whatsapp', 'netflix', 'sbi', 'hdfc', 'icici', 'axisbank',
  'kotak', 'paytm', 'phonepe', 'flipkart', 'irctc', 'uidai', 'incometax',
];

/// Returns why an address looks like a phishing trick, or null if it looks normal.
String? suspiciousReason(String url) {
  final u = Uri.tryParse(url);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return null;
  final host = u.host.toLowerCase();
  if (host.isEmpty) return null;
  if (u.userInfo.isNotEmpty) {
    return 'The address hides extra text before "@". This trick is used to '
        'disguise the real site, which is $host.';
  }
  if (host.split('.').any((l) => l.startsWith('xn--'))) {
    return 'The address uses look-alike international characters. '
        'It may imitate a well-known site.';
  }
  if (isIpAddress(host)) {
    return 'This site is a bare IP address with no domain name.';
  }
  final main = registrableDomain(host);
  final sub =
      host.length > main.length ? host.substring(0, host.length - main.length) : '';
  for (final b in _brands) {
    if (sub.contains(b) && !main.contains(b)) {
      return 'The address mentions "$b", but the real site is $main.';
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Downloads
// ---------------------------------------------------------------------------

enum DownloadRisk { safe, warn, block }

class DownloadVerdict {
  const DownloadVerdict(this.risk, [this.reason = '']);
  final DownloadRisk risk;
  final String reason;
}

/// Script and shortcut types that are never downloaded.
const Set<String> alwaysBlockedExtensions = <String>{
  'scr', 'pif', 'cpl', 'hta', 'vbs', 'vbe', 'jse', 'wsf', 'wsh', 'lnk',
  'reg', 'msc', 'ps1', 'psm1', 'scf', 'inf',
};

/// Program and installer types: allowed only after a warning.
const Set<String> executableExtensions = <String>{
  'apk', 'xapk', 'apks', 'aab', 'exe', 'msi', 'msix', 'msixbundle', 'appx',
  'appxbundle', 'bat', 'cmd', 'com', 'dll', 'jar', 'js', 'iso', 'img', 'vhd',
  'dmg',
};

const Set<String> _documentExtensions = <String>{
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'jpg', 'jpeg',
  'png', 'gif', 'mp3', 'mp4', 'zip', 'csv',
};

DownloadVerdict checkDownload(String fileName, String url,
    {bool fromDangerousSite = false}) {
  if (fromDangerousSite) {
    return const DownloadVerdict(
        DownloadRisk.block, 'it comes from a site reported as dangerous');
  }
  final lower = fileName.toLowerCase().trim();
  final parts = lower.split('.');
  final ext = parts.length > 1 ? parts.last.trim() : '';
  if (alwaysBlockedExtensions.contains(ext)) {
    return DownloadVerdict(
        DownloadRisk.block, '.$ext files can run harmful scripts');
  }
  final isProgram = executableExtensions.contains(ext);
  if (isProgram &&
      parts.length > 2 &&
      _documentExtensions.contains(parts[parts.length - 2].trim())) {
    return const DownloadVerdict(
        DownloadRisk.block, 'it is a program disguised as a document');
  }
  if (lower.contains('\u202e') || (isProgram && lower.contains('   '))) {
    return const DownloadVerdict(
        DownloadRisk.block, 'its name hides the real file type');
  }
  if (isProgram && Uri.tryParse(url)?.scheme == 'http') {
    return const DownloadVerdict(DownloadRisk.block,
        'programs sent over an insecure (http) connection can be tampered with');
  }
  if (isProgram) {
    return DownloadVerdict(
        DownloadRisk.warn, '.$ext files can install or run software');
  }
  return const DownloadVerdict(DownloadRisk.safe);
}

// ---------------------------------------------------------------------------
// Block lists
// ---------------------------------------------------------------------------

/// Sites that must never be blocked as trackers (would break normal browsing).
const Set<String> neverBlockDomains = <String>{
  'google.com', 'google.co.in', 'gstatic.com', 'googleapis.com',
  'youtube.com', 'ytimg.com', 'facebook.com', 'fbcdn.net', 'instagram.com',
  'whatsapp.com', 'microsoft.com', 'live.com', 'office.com', 'bing.com',
  'apple.com', 'icloud.com', 'amazon.com', 'amazon.in', 'twitter.com',
  'x.com', 'twimg.com', 'linkedin.com', 'licdn.com', 'github.com',
  'githubusercontent.com', 'duckduckgo.com', 'wikipedia.org', 'cloudflare.com',
  'akamaihd.net', 'jsdelivr.net', 'unpkg.com',
};

/// Reads hosts-file or one-domain-per-line lists.
Set<String> parseHostList(String text) {
  final out = <String>{};
  for (var line in const LineSplitter().convert(text)) {
    final hash = line.indexOf('#');
    if (hash >= 0) line = line.substring(0, hash);
    line = line.trim();
    if (line.isEmpty || line.startsWith('!')) continue;
    final parts = line.split(RegExp(r'\s+'));
    var host = (parts.length >= 2 &&
            (parts[0] == '0.0.0.0' || parts[0] == '127.0.0.1' || parts[0] == '::1'))
        ? parts[1]
        : parts[0];
    host = host.toLowerCase();
    if (host.startsWith('||')) host = host.substring(2);
    if (host.endsWith('^')) host = host.substring(0, host.length - 1);
    if (host.startsWith('*.')) host = host.substring(2);
    if (host == 'localhost' || host.endsWith('.localdomain')) continue;
    if (isValidHost(host)) out.add(host);
    if (out.length >= 400000) break;
  }
  return out;
}

/// Reads the Disconnect tracking-protection list (the one Firefox uses).
Set<String> parseDisconnect(String json) {
  const wanted = <String>{
    'Advertising', 'Analytics', 'Cryptomining', 'Fingerprinting',
    'FingerprintingInvasive', 'FingerprintingGeneral',
  };
  final out = <String>{};
  Object? root;
  try {
    root = jsonDecode(json);
  } catch (_) {
    return out;
  }
  if (root is! Map) return out;
  final cats = root['categories'];
  if (cats is! Map) return out;
  for (final entry in cats.entries) {
    if (!wanted.contains(entry.key)) continue;
    final companies = entry.value;
    if (companies is! List) continue;
    for (final company in companies) {
      if (company is! Map) continue;
      for (final sites in company.values) {
        if (sites is! Map) continue;
        for (final v in sites.values) {
          if (v is! List) continue;
          for (final d in v) {
            if (d is! String) continue;
            final h = d.trim().toLowerCase();
            if (isValidHost(h) && !neverBlockDomains.contains(h)) out.add(h);
          }
        }
      }
    }
  }
  return out;
}

/// Groups domains into a few regular expressions for the WebView blocker.
List<String> buildTrackerPatterns(Iterable<String> domains, {int chunk = 250}) {
  final valid = domains.where(isValidHost).toList();
  final out = <String>[];
  for (var i = 0; i < valid.length; i += chunk) {
    final part = valid.sublist(i, math.min(i + chunk, valid.length));
    out.add(r'^https?://([^/?#]*\.)?(' +
        part.map((d) => d.replaceAll('.', r'\.')).join('|') +
        r')([/:?#]|$)');
  }
  return out;
}
