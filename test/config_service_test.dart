import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/config_service.dart';

void main() {
  group('runtime settings', () {
    test('loads runtime settings without quoted display values', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mise-gui-config-',
      );
      addTearDown(() async => tempDir.delete(recursive: true));
      final configFile = File('${tempDir.path}/.config/mise/config.toml');
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString('''
[settings]
http_timeout = "30s"
http_retries = 2
yes = false
''');

      final service = LiveConfigService(homeDirectory: tempDir.path);
      final workspace = await service.fetchWorkspace(
        includeProjectConfig: false,
      );

      final settings = workspace.runtimeSettings!;
      expect(settings.document.path, configFile.path);
      expect(settings.recordFor('http_timeout').displayValue, '30s');
      expect(settings.recordFor('http_retries').displayValue, '2');
      expect(settings.recordFor('yes').displayValue, 'false');
    });

    test('adds a settings section when saving runtime settings', () async {
      const service = LiveConfigService();
      const document = ConfigDocumentData(
        id: 'global',
        title: '全局 TOML',
        path: '/tmp/config.toml',
        content: '[tools]\nnode = "22"\n',
        description: '全局配置',
        commandPreview: 'cat /tmp/config.toml',
        exists: true,
      );

      final preview = await service.previewRuntimeSettingsSave(
        document: document,
        values: const {'http_timeout': '30s', 'jobs': '4'},
      );

      expect(preview.hasChanges, isTrue);
      expect(preview.nextContent, contains('[tools]\nnode = "22"\n'));
      expect(preview.nextContent, contains('[settings]\n'));
      expect(preview.nextContent, contains('http_timeout = "30s"\n'));
      expect(preview.nextContent, contains('jobs = 4\n'));
    });

    test('updates existing settings while preserving comments and unknown keys', () async {
      const service = LiveConfigService();
      const document = ConfigDocumentData(
        id: 'global',
        title: '全局 TOML',
        path: '/tmp/config.toml',
        content: '''
[tools]
node = "22"

[settings]
# network tuning
http_timeout = "20s"
plugin_autoupdate_last_check_duration = "1 week"
yes = true

[env]
RUST_LOG = "info"
''',
        description: '全局配置',
        commandPreview: 'cat /tmp/config.toml',
        exists: true,
      );

      final preview = await service.previewRuntimeSettingsSave(
        document: document,
        values: const {
          'http_timeout': '45s',
          'http_retries': '3',
          'yes': null,
        },
      );

      expect(preview.nextContent, contains('# network tuning\n'));
      expect(preview.nextContent, contains('http_timeout = "45s"\n'));
      expect(preview.nextContent, contains('http_retries = 3\n'));
      expect(
        preview.nextContent,
        contains('plugin_autoupdate_last_check_duration = "1 week"\n'),
      );
      expect(preview.nextContent, isNot(contains('yes = true')));
      expect(preview.nextContent, contains('[env]\nRUST_LOG = "info"\n'));
    });

    test('formats boolean and string runtime settings as TOML scalars', () async {
      const service = LiveConfigService();
      const document = ConfigDocumentData(
        id: 'global',
        title: '全局 TOML',
        path: '/tmp/config.toml',
        content: '[settings]\n',
        description: '全局配置',
        commandPreview: 'cat /tmp/config.toml',
        exists: true,
      );

      final preview = await service.previewRuntimeSettingsSave(
        document: document,
        values: const {
          'experimental': 'true',
          'paranoid': 'false',
          'env_file': '.env.local',
        },
      );

      expect(preview.nextContent, contains('experimental = true\n'));
      expect(preview.nextContent, contains('paranoid = false\n'));
      expect(preview.nextContent, contains('env_file = ".env.local"\n'));
    });

    test('does not create an empty settings section when all values are unset', () async {
      const service = LiveConfigService();
      const document = ConfigDocumentData(
        id: 'global',
        title: '全局 TOML',
        path: '/tmp/config.toml',
        content: '[tools]\nnode = "22"\n',
        description: '全局配置',
        commandPreview: 'cat /tmp/config.toml',
        exists: true,
      );

      final preview = await service.previewRuntimeSettingsSave(
        document: document,
        values: const {'http_timeout': null, 'jobs': null},
      );

      expect(preview.hasChanges, isFalse);
      expect(preview.nextContent, '[tools]\nnode = "22"\n');
    });
  });
}
