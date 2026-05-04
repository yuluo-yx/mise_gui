import 'package:mise_gui/models/app_models.dart';
import 'package:package_info_plus/package_info_plus.dart';

abstract class AppReleaseService {
  Future<AppVersionInfo> load();
}

class PackageInfoAppReleaseService implements AppReleaseService {
  const PackageInfoAppReleaseService();

  @override
  Future<AppVersionInfo> load() async {
    final info = await PackageInfo.fromPlatform();

    return AppVersionInfo(
      appName: info.appName,
      packageName: info.packageName,
      version: info.version,
      buildNumber: info.buildNumber,
    );
  }
}
