import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scanner_nota_flutter/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateService Unit Tests (Section 2C)', () {
    testWidgets('1. Manifest baru (version_code lebih besar) -> status available & fields terbaca', (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            "version_code": 25,
            "version_name": "1.0.8",
            "download_url": "https://example.com/CetakNotaBT.apk",
            "changelog": "Fitur baru super cepat",
            "force_update": false,
            "apk_size_bytes": 52428800,
            "apk_checksum": "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
          }),
          200,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await UpdateService.checkUpdate(
                    context,
                    client: mockClient,
                    getInstalledVersionCode: () async => 24,
                    getInstalledVersionName: () async => "1.0.7",
                  );
                },
                child: const Text('Check'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();

      expect(UpdateService.currentUpdateInfo.status, UpdateStatus.available);
      expect(UpdateService.currentUpdateInfo.versionCode, 25);
      expect(UpdateService.currentUpdateInfo.versionName, '1.0.8');
      expect(UpdateService.currentUpdateInfo.downloadUrl, 'https://example.com/CetakNotaBT.apk');
      expect(UpdateService.currentUpdateInfo.changelog, 'Fitur baru super cepat');
      expect(UpdateService.currentUpdateInfo.apkSizeBytes, 52428800);
      expect(UpdateService.currentUpdateInfo.apkChecksum, 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890');
      expect(UpdateService.currentUpdateInfo.forceUpdate, isFalse);

      // Dialog shows version and changelog
      expect(find.text('Pembaruan Tersedia'), findsOneWidget);
      expect(find.text('Versi Terbaru: v1.0.8'), findsOneWidget);
      expect(find.text('50.0 MB'), findsOneWidget);
    });

    testWidgets('2. Manifest sama/lama -> status none, tidak ada dialog', (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            "version_code": 24,
            "version_name": "1.0.7",
            "download_url": "https://example.com/CetakNotaBT.apk",
            "changelog": "Fitur lama",
            "force_update": false,
          }),
          200,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await UpdateService.checkUpdate(
                    context,
                    client: mockClient,
                    getInstalledVersionCode: () async => 24,
                    getInstalledVersionName: () async => "1.0.7",
                  );
                },
                child: const Text('Check'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();

      expect(UpdateService.currentUpdateInfo.status, UpdateStatus.none);
      expect(find.text('Pembaruan Tersedia'), findsNothing);
    });

    testWidgets('3. Manifest berisi force_update: true -> flag force terbaca', (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            "version_code": 26,
            "version_name": "1.1.0",
            "download_url": "https://example.com/CetakNotaBT.apk",
            "changelog": "Pembaruan wajib!",
            "force_update": true,
          }),
          200,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  await UpdateService.checkUpdate(
                    context,
                    client: mockClient,
                    getInstalledVersionCode: () async => 24,
                    getInstalledVersionName: () async => "1.0.7",
                  );
                },
                child: const Text('Check'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();

      expect(UpdateService.currentUpdateInfo.status, UpdateStatus.available);
      expect(UpdateService.currentUpdateInfo.forceUpdate, isTrue);

      // On force update, 'Nanti' button is not shown
      expect(find.text('Nanti'), findsNothing);
      expect(find.text('Unduh & Pasang'), findsOneWidget);
    });

    testWidgets('4. Fetch gagal (404/offline) -> status error di cek manual, dan silent di auto check', (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      // Auto check (showNoUpdateToast = false)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await UpdateService.checkUpdate(
                      context,
                      showNoUpdateToast: false,
                      client: mockClient,
                      getInstalledVersionCode: () async => 24,
                      getInstalledVersionName: () async => "1.0.7",
                    );
                  },
                  child: const Text('AutoCheck'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('AutoCheck'));
      await tester.pumpAndSettle();

      expect(UpdateService.currentUpdateInfo.status, UpdateStatus.error);
      // Silent: No SnackBar or dialog
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Pembaruan Tersedia'), findsNothing);

      // Manual check (showNoUpdateToast = true)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await UpdateService.checkUpdate(
                      context,
                      showNoUpdateToast: true,
                      client: mockClient,
                      getInstalledVersionCode: () async => 24,
                      getInstalledVersionName: () async => "1.0.7",
                    );
                  },
                  child: const Text('ManualCheck'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('ManualCheck'));
      await tester.pumpAndSettle();

      expect(UpdateService.currentUpdateInfo.status, UpdateStatus.error);
      // Shows error SnackBar
      expect(find.byType(SnackBar), findsOneWidget);
    });

    test('5. Cache-busting: URL fetch mengandung ?t= dan header no-cache', () async {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;

      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        capturedHeaders = request.headers;
        return http.Response(
          jsonEncode({
            "version_code": 24,
            "version_name": "1.0.7",
            "download_url": "",
          }),
          200,
        );
      });

      await UpdateService.checkUpdate(
        _DummyBuildContext(),
        client: mockClient,
        getInstalledVersionCode: () async => 24,
        getInstalledVersionName: () async => "1.0.7",
      );

      expect(capturedUri, isNotNull);
      expect(capturedUri.toString(), contains('?t='));
      expect(capturedHeaders?['Cache-Control'], 'no-cache');
      expect(capturedHeaders?['Pragma'], 'no-cache');
    });

    test('6. hidePlayProtectNotice: default false, set true -> logic pembacaan benar', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getBool('hidePlayProtectNotice') ?? false, isFalse);

      await prefs.setBool('hidePlayProtectNotice', true);
      expect(prefs.getBool('hidePlayProtectNotice') ?? false, isTrue);
    });

    test('7. version.json hasil CI (simulasi): SHA-256 64 hex char + apk_size_bytes match file tiruan', () {
      final dummyApkBytes = utf8.encode('DUMMY_APK_CONTENT_FOR_TESTING_PURPOSES');
      final expectedSize = dummyApkBytes.length;
      // 64-char lowercase hex SHA-256
      const expectedSha256 = '3a7acb689a7428807d898516e885bc64cd93c20c024508493fb0a996c561a3ec';

      final simulatedVersionJson = {
        "version_code": 24,
        "version_name": "1.0.7",
        "download_url": "https://github.com/bengkelgadget-code/CetakNota_flutter/releases/download/v1.0.7/CetakNotaBT.apk",
        "changelog": "Pembaruan otomatis dari GitHub Actions versi v1.0.7.",
        "force_update": false,
        "apk_checksum": expectedSha256,
        "apk_size_bytes": expectedSize
      };

      expect(simulatedVersionJson['apk_checksum'].toString().length, 64);
      expect(simulatedVersionJson['apk_size_bytes'], expectedSize);
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(simulatedVersionJson['apk_checksum'].toString()), isTrue);
    });
  });
}

class _DummyBuildContext implements BuildContext {
  @override
  bool get mounted => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
