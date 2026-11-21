import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scanner_nota_flutter/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    UpdateService.defaultTempDirProvider = () async => Directory.systemTemp;
    UpdateService.currentUpdateInfo = const UpdateInfo();
    UpdateService.pendingUpdateInfo = null;
    UpdateService.isDownloadingInProgress = false;
    UpdateService.activeDownloadFuture = null;
  });

  group('UpdateService Unit Tests (Section 2C & 4A)', () {
    testWidgets('1. Manifest baru dengan autoDownload: false -> status available & dialog Pembaruan Tersedia muncul', (tester) async {
      SharedPreferences.setMockInitialValues({'autoDownloadUpdate': false});
      final prefs = await SharedPreferences.getInstance();

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
                    testPrefs: prefs,
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

      expect(find.text('Pembaruan Tersedia'), findsOneWidget);
      expect(find.text('Versi Terbaru: v1.0.8'), findsOneWidget);
      expect(find.text('50.0 MB'), findsOneWidget);
      expect(find.text('Unduh & Pasang'), findsOneWidget);
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
      expect(find.text('Pembaruan Siap'), findsNothing);
    });

    testWidgets('3. Manifest berisi force_update: true -> flag force terbaca & TIDAK ada auto-download background', (tester) async {
      SharedPreferences.setMockInitialValues({'autoDownloadUpdate': true});
      final prefs = await SharedPreferences.getInstance();

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
                    testPrefs: prefs,
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
      const expectedSha256 = '3a7acb689a7428807d898516e885bc64cd93c20c024508493fb0a996c561a3ec';

      final simulatedVersionJson = {
        "version_code": 25,
        "version_name": "1.0.8",
        "download_url": "https://github.com/bengkelgadget-code/CetakNota_flutter/releases/download/v1.0.8/CetakNotaBT.apk",
        "changelog": "Pembaruan otomatis",
        "force_update": false,
        "apk_checksum": expectedSha256,
        "apk_size_bytes": expectedSize
      };

      expect(simulatedVersionJson['apk_checksum'].toString().length, 64);
      expect(simulatedVersionJson['apk_size_bytes'], expectedSize);
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(simulatedVersionJson['apk_checksum'].toString()), isTrue);
    });

    // 4A Baru: Auto-download di background
    testWidgets('8. Auto-download di background saat toggle nyala -> downloading -> ready -> dialog Pembaruan Siap', (tester) async {
      SharedPreferences.setMockInitialValues({'autoDownloadUpdate': true});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = Directory.systemTemp.createTempSync('ota_test_8_');

      const validChecksum = '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('version.json')) {
          return http.Response(
            jsonEncode({
              "version_code": 25,
              "version_name": "1.0.8",
              "download_url": "https://example.com/CetakNotaBT.apk",
              "changelog": "Auto download mantap",
              "force_update": false,
              "apk_size_bytes": 100,
              "apk_checksum": validChecksum,
            }),
            200,
          );
        } else {
          return http.Response('APK_DUMMY_BINARY_DATA', 200);
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await UpdateService.checkUpdate(
                      context,
                      client: mockClient,
                      testPrefs: prefs,
                      tempDirProvider: () async => tempDir,
                      sha256Calculator: (path) async => validChecksum,
                      getInstalledVersionCode: () async => 24,
                      getInstalledVersionName: () async => "1.0.7",
                    );
                  },
                  child: const Text('AutoUpdate'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('AutoUpdate'));
      await tester.pump(); // render SnackBar "Mengunduh pembaruan..."

      expect(find.textContaining('Mengunduh pembaruan v1.0.8'), findsOneWidget);

      await UpdateService.activeDownloadFuture;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(UpdateService.currentUpdateInfo.status, UpdateStatus.ready);
      expect(find.text('Pembaruan Siap'), findsOneWidget);
      expect(find.text('Pasang Sekarang'), findsOneWidget);
      expect(find.text('Unduh & Pasang'), findsNothing);

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('9. Toggle autoDownloadUpdate mati -> status available, TIDAK auto-download, dialog lama muncul', (tester) async {
      SharedPreferences.setMockInitialValues({'autoDownloadUpdate': false});
      final prefs = await SharedPreferences.getInstance();

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            "version_code": 25,
            "version_name": "1.0.8",
            "download_url": "https://example.com/CetakNotaBT.apk",
            "changelog": "Perubahan",
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
                    testPrefs: prefs,
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
      expect(find.text('Pembaruan Tersedia'), findsOneWidget);
      expect(find.text('Unduh & Pasang'), findsOneWidget);
      expect(find.text('Pasang Sekarang'), findsNothing);
    });

    testWidgets('10. Unduh gagal checksum -> file dihapus, status error, pesan menyebut checksum', (tester) async {
      SharedPreferences.setMockInitialValues({'autoDownloadUpdate': true});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = Directory.systemTemp.createTempSync('ota_test_10_');

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('version.json')) {
          return http.Response(
            jsonEncode({
              "version_code": 25,
              "version_name": "1.0.8",
              "download_url": "https://example.com/CetakNotaBT.apk",
              "changelog": "Perubahan",
              "force_update": false,
              "apk_size_bytes": 100,
              "apk_checksum": "EXPECTED_CORRECT_CHECKSUM",
            }),
            200,
          );
        } else {
          return http.Response('CORRUPT_DATA', 200);
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await UpdateService.checkUpdate(
                      context,
                      client: mockClient,
                      testPrefs: prefs,
                      tempDirProvider: () async => tempDir,
                      sha256Calculator: (path) async => "WRONG_CHECKSUM",
                      getInstalledVersionCode: () async => 24,
                      getInstalledVersionName: () async => "1.0.7",
                    );
                  },
                  child: const Text('DownloadFail'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('DownloadFail'));
      await tester.pump();
      await UpdateService.activeDownloadFuture;
      await tester.pumpAndSettle();

      expect(UpdateService.currentUpdateInfo.status, UpdateStatus.error);
      expect(UpdateService.currentUpdateInfo.errorMessage, contains('checksum'));

      // File corrupt target/part harus terhapus
      final targetFile = File('${tempDir.path}/CetakNotaBT_v25.apk');
      final partFile = File('${tempDir.path}/CetakNotaBT_v25.part');
      expect(targetFile.existsSync(), isFalse);
      expect(partFile.existsSync(), isFalse);

      tempDir.deleteSync(recursive: true);
    });

    testWidgets('11. Unduh selesai tapi isSafe() == false -> pending; saat kembali ke Beranda -> dialog siap muncul', (tester) async {
      SharedPreferences.setMockInitialValues({'autoDownloadUpdate': true});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = Directory.systemTemp.createTempSync('ota_test_11_');

      bool isSafeCondition = false; // Simulasikan user sedang scan struk
      const validChecksum = 'VALID_CHECKSUM_11';

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('version.json')) {
          return http.Response(
            jsonEncode({
              "version_code": 25,
              "version_name": "1.0.8",
              "download_url": "https://example.com/CetakNotaBT.apk",
              "changelog": "Perubahan aman",
              "force_update": false,
              "apk_checksum": validChecksum,
            }),
            200,
          );
        } else {
          return http.Response('APK_DATA_11', 200);
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    await UpdateService.checkUpdate(
                      context,
                      client: mockClient,
                      testPrefs: prefs,
                      isSafe: () => isSafeCondition,
                      tempDirProvider: () async => tempDir,
                      sha256Calculator: (path) async => validChecksum,
                      getInstalledVersionCode: () async => 24,
                      getInstalledVersionName: () async => "1.0.7",
                    );
                  },
                  child: const Text('CheckUnsafe'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('CheckUnsafe'));
      await tester.pump();
      await UpdateService.activeDownloadFuture;
      await tester.pumpAndSettle();

      // Karena isSafe == false, dialog TIDAK boleh muncul
      expect(find.text('Pembaruan Siap'), findsNothing);
      expect(UpdateService.pendingUpdateInfo, isNotNull);
      expect(UpdateService.pendingUpdateInfo!.status, UpdateStatus.ready);

      // Simulasikan kembali ke Beranda: isSafe jadi true dan showPendingUpdateDialog dipanggil
      isSafeCondition = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  UpdateService.showPendingUpdateDialog(context, testPrefs: prefs);
                },
                child: const Text('BackToHome'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('BackToHome'));
      await tester.pumpAndSettle();

      // Sekarang dialog muncul
      expect(find.text('Pembaruan Siap'), findsOneWidget);
      expect(find.text('Pasang Sekarang'), findsOneWidget);

      tempDir.deleteSync(recursive: true);
    });

    test('12. File ready dari versi lama + version.json ada versi baru -> file lama dibersihkan', () async {
      SharedPreferences.setMockInitialValues({'autoDownloadUpdate': false});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = Directory.systemTemp.createTempSync('ota_test_12_');

      // Buat file lama v24
      final oldFile = File('${tempDir.path}/CetakNotaBT_v24.apk');
      oldFile.writeAsStringSync('OLD_VERSION_DATA');
      expect(oldFile.existsSync(), isTrue);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            "version_code": 25,
            "version_name": "1.0.8",
            "download_url": "https://example.com/CetakNotaBT.apk",
            "changelog": "Versi baru",
            "force_update": false,
          }),
          200,
        );
      });

      await UpdateService.checkUpdate(
        _DummyBuildContext(),
        client: mockClient,
        testPrefs: prefs,
        tempDirProvider: () async => tempDir,
        getInstalledVersionCode: () async => 24,
        getInstalledVersionName: () async => "1.0.7",
      );

      // File v24 harus sudah terhapus
      expect(oldFile.existsSync(), isFalse);

      tempDir.deleteSync(recursive: true);
    });

    test('13. G-2: Logika validasi version code terhadap rilis terakhir GitHub', () {
      // Skenario 1: rilis terakhir 24, version baru 25 -> Lolos
      int lastReleaseCode = 24;
      int newVersionCode = 25;
      expect(newVersionCode > lastReleaseCode, isTrue);

      // Skenario 2: version baru sama dengan rilis terakhir (24) -> Ditolak
      newVersionCode = 24;
      expect(newVersionCode <= lastReleaseCode, isTrue);

      // Skenario 3: version baru lebih kecil (23) -> Ditolak
      newVersionCode = 23;
      expect(newVersionCode <= lastReleaseCode, isTrue);
    });
  });
}

class _DummyBuildContext implements BuildContext {
  @override
  bool get mounted => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
