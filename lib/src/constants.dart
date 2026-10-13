/// App-wide constants. APP_VERSION is injected by the CI build.
const String appName = 'JKBrowseSafe';
const String appVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '1.2.0-dev');
const String kDesktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
