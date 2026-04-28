import 'package:agenda_trabalho/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateService', () {
    final service = AppUpdateService();

    test('compares semantic versions with optional v prefix', () {
      expect(service.compareVersions('1.0.1', 'v1.0.2'), -1);
      expect(service.compareVersions('1.2.0', '1.2'), 0);
      expect(service.compareVersions('2.0.0', '1.9.9'), 1);
    });
  });
}
