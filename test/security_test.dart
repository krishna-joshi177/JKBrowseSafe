import 'package:flutter_test/flutter_test.dart';
import 'package:safe_browser/src/security.dart';

void main() {
  test('real (registrable) domain', () {
    expect(registrableDomain('a.b.example.com'), 'example.com');
    expect(registrableDomain('login.sbi.co.in'), 'sbi.co.in');
    expect(registrableDomain('paypal.com.secure-login.xyz'), 'secure-login.xyz');
    expect(registrableDomain('localhost'), 'localhost');
  });

  test('look-alike addresses are flagged', () {
    expect(suspiciousReason('https://paypal.com.secure-login.xyz/'), isNotNull);
    expect(suspiciousReason('https://xn--pypal-4ve.com/'), isNotNull);
    expect(suspiciousReason('https://user@evil.com/'), isNotNull);
    expect(suspiciousReason('http://203.0.113.9/login'), isNotNull);
    expect(suspiciousReason('https://www.paypal.com/'), isNull);
    expect(suspiciousReason('https://mail.google.com/'), isNull);
  });

  test('host matching includes sub-domains only', () {
    final set = <String>{'evil.com'};
    expect(hostInSet(set, 'a.b.evil.com'), isTrue);
    expect(hostInSet(set, 'evil.com'), isTrue);
    expect(hostInSet(set, 'notevil.com'), isFalse);
  });

  test('dangerous downloads', () {
    expect(checkDownload('report.pdf', 'https://a.com/report.pdf').risk,
        DownloadRisk.safe);
    expect(checkDownload('app.apk', 'https://a.com/app.apk').risk,
        DownloadRisk.warn);
    expect(checkDownload('app.apk', 'http://a.com/app.apk').risk,
        DownloadRisk.block);
    expect(checkDownload('invoice.pdf.exe', 'https://a.com/x').risk,
        DownloadRisk.block);
    expect(checkDownload('run.vbs', 'https://a.com/x').risk, DownloadRisk.block);
    expect(
        checkDownload('photo.zip', 'https://a.com/x', fromDangerousSite: true)
            .risk,
        DownloadRisk.block);
  });

  test('hosts lists are parsed', () {
    const text = '''
# comment
0.0.0.0 0.0.0.0
0.0.0.0 bad.example.com
127.0.0.1 evil.test.org  # trailing comment
phish.example.net
0.0.0.0 localhost
||ads.example.org^
''';
    expect(parseHostList(text),
        {'bad.example.com', 'evil.test.org', 'phish.example.net', 'ads.example.org'});
  });

  test('Disconnect list is parsed', () {
    const json = '{"categories":{'
        '"Advertising":[{"AdCo":{"https://adco.com/":["adco.com","ads.adco.net"],"performance":"true"}}],'
        '"Content":[{"Vid":{"https://vid.com/":["vid.com"]}}],'
        '"Analytics":[{"Stat":{"https://stat.io/":["stat.io","google.com"]}}]}}';
    expect(parseDisconnect(json), {'adco.com', 'ads.adco.net', 'stat.io'});
    expect(parseDisconnect('not json'), isEmpty);
  });

  test('tracker patterns match sub-domains only', () {
    final p = buildTrackerPatterns(['doubleclick.net', 'stat.io'], chunk: 1);
    expect(p.length, 2);
    final re = RegExp(p.first);
    expect(re.hasMatch('https://ad.doubleclick.net/x'), isTrue);
    expect(re.hasMatch('https://doubleclick.net'), isTrue);
    expect(re.hasMatch('https://notdoubleclick.net/'), isFalse);
    expect(re.hasMatch('https://example.com/?u=doubleclick.net'), isFalse);
  });
}
