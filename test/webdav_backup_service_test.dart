import 'package:flutter_test/flutter_test.dart';
import 'package:nnez_yisu/services/webdav_backup_service.dart';

void main() {
  group('WebDAV backup target', () {
    test('keeps encoded directory paths encoded once', () {
      const config = WebDavConfig(
        url: 'https://example.com/dav/%E4%B8%80%E7%B2%9F',
        username: 'user',
        password: 'password',
      );

      final target = WebDavBackupService.instance.resolveTarget(config);

      expect(
        target.collectionUri.toString(),
        'https://example.com/dav/%E4%B8%80%E7%B2%9F/yisu/',
      );
      expect(target.fileName, 'yisu_backup.json');
    });

    test('creates an app-owned yisu directory below a WebDAV root', () {
      const config = WebDavConfig(
        url: 'https://example.com/dav/',
        username: 'user',
        password: 'password',
      );

      final target = WebDavBackupService.instance.resolveTarget(config);

      expect(target.collectionUri.toString(), 'https://example.com/dav/yisu/');
      expect(target.fileName, 'yisu_backup.json');
    });

    test('does not append the yisu directory twice', () {
      const config = WebDavConfig(
        url: 'https://example.com/dav/yisu/',
        username: 'user',
        password: 'password',
      );

      final target = WebDavBackupService.instance.resolveTarget(config);

      expect(target.collectionUri.toString(), 'https://example.com/dav/yisu/');
    });

    test('accepts an explicit JSON file URL', () {
      const config = WebDavConfig(
        url: 'https://example.com/dav/campus-card.json',
        username: 'user',
        password: 'password',
      );

      final target = WebDavBackupService.instance.resolveTarget(config);

      expect(target.collectionUri.toString(), 'https://example.com/dav/');
      expect(target.fileName, 'campus-card.json');
      expect(target.fileStem, 'campus-card');
    });

    test('uses the explicit file stem for timestamped backups', () {
      const config = WebDavConfig(
        url: 'https://example.com/dav/campus-card.json',
        username: 'user',
        password: 'password',
        mode: WebDavBackupMode.createNew,
      );

      final target = WebDavBackupService.instance.resolveTarget(
        config,
        now: DateTime(2026, 7, 18, 12, 34, 56),
      );

      expect(target.fileName, 'campus-card_20260718_123456.json');
    });
  });
}
