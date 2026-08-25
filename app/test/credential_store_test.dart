import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/storage/credential_store.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('CredentialStore', () {
    test('初始狀態下帳號與密碼皆為 null', () async {
      final store = CredentialStore();
      expect(await store.readUsername(), isNull);
      expect(await store.readPassword(), isNull);
    });

    test('saveUsername 與 readUsername 正常存取', () async {
      final store = CredentialStore();
      await store.saveUsername('B11234567');
      expect(await store.readUsername(), 'B11234567');
    });

    test('savePassword 與 readPassword 正常存取', () async {
      final store = CredentialStore();
      await store.savePassword('secret123');
      expect(await store.readPassword(), 'secret123');
    });

    test('clearPassword 只刪除密碼，保留帳號', () async {
      final store = CredentialStore();
      await store.saveUsername('B11234567');
      await store.savePassword('secret123');

      await store.clearPassword();

      expect(await store.readUsername(), 'B11234567');
      expect(await store.readPassword(), isNull);
    });

    test('clearAll 同時清空帳號與密碼', () async {
      final store = CredentialStore();
      await store.saveUsername('B11234567');
      await store.savePassword('secret123');

      await store.clearAll();

      expect(await store.readUsername(), isNull);
      expect(await store.readPassword(), isNull);
    });
  });
}
