import 'package:package_info_plus/package_info_plus.dart';

/// The installed version. Read once at launch ([init]) so screens can show it
/// immediately instead of waiting a frame for a platform call.
class AppInfo {
  AppInfo._();

  /// The pubspec version until [init] has run, or if the platform can't answer.
  static ({String version, String build}) current = (version: '1.0.0', build: '1');

  static String get label => '${current.version} (${current.build})';

  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      current = (version: info.version, build: info.buildNumber);
    } catch (_) {
      // Keep the fallback.
    }
  }
}
