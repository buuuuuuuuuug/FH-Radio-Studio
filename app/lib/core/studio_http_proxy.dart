import 'dart:io';
import 'system_proxy.dart';

/// Dart HttpClient does not automatically use Windows Internet Settings.
/// Apply the user's existing proxy to catalog, covers and audio alike; keep
/// normal certificate validation and bypass local requests.
class StudioHttpProxy extends HttpOverrides {
  StudioHttpProxy(this.environment);
  final Map<String, String> environment;
  static Future<void> install() async {
    final env = Map<String, String>.from(Platform.environment);
    if (Platform.isWindows) {
      try {
        final result = await Process.run('reg', const [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        ]).timeout(const Duration(seconds: 2));
        final config = result.exitCode == 0
            ? SystemProxyConfig.fromWindowsRegistryOutput('${result.stdout}')
            : null;
        if (config != null) env.addAll(config.toEnvironment());
      } on Object {
        // Environment proxies/direct connections remain available.
      }
    }
    final bypass = mergeNoProxyEntries([
      env['NO_PROXY'],
      env['no_proxy'],
      'localhost,127.0.0.1,::1',
    ]);
    env['NO_PROXY'] = bypass;
    env['no_proxy'] = bypass;
    HttpOverrides.global = StudioHttpProxy(env);
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionTimeout = const Duration(seconds: 18)
        ..findProxy = (uri) =>
            HttpClient.findProxyFromEnvironment(uri, environment: environment);
}
