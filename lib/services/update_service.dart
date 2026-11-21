import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UpdateStatus {
  none,
  checking,
  available,
  downloading,
  ready,
  error,
}

class UpdateInfo {
  final UpdateStatus status;
  final int versionCode;
  final String versionName;
  final String downloadUrl;
  final String changelog;
  final bool forceUpdate;
  final int? apkSizeBytes;
  final String? apkChecksum;
  final double progress;
  final String? errorMessage;
  final String? localApkPath;

  const UpdateInfo({
    this.status = UpdateStatus.none,
    this.versionCode = 0,
    this.versionName = '',
    this.downloadUrl = '',
    this.changelog = '',
    this.forceUpdate = false,
    this.apkSizeBytes,
    this.apkChecksum,
    this.progress = 0.0,
    this.errorMessage,
    this.localApkPath,
  });

  UpdateInfo copyWith({
    UpdateStatus? status,
    int? versionCode,
    String? versionName,
    String? downloadUrl,
    String? changelog,
    bool? forceUpdate,
    int? apkSizeBytes,
    String? apkChecksum,
    double? progress,
    String? errorMessage,
    String? localApkPath,
  }) {
    return UpdateInfo(
      status: status ?? this.status,
      versionCode: versionCode ?? this.versionCode,
      versionName: versionName ?? this.versionName,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      changelog: changelog ?? this.changelog,
      forceUpdate: forceUpdate ?? this.forceUpdate,
      apkSizeBytes: apkSizeBytes ?? this.apkSizeBytes,
      apkChecksum: apkChecksum ?? this.apkChecksum,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      localApkPath: localApkPath ?? this.localApkPath,
    );
  }
}

class UpdateService {
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/bengkelgadget-code/CetakNota_flutter/main/version.json';

  static UpdateInfo currentUpdateInfo = const UpdateInfo();
  static UpdateInfo? pendingUpdateInfo;
  static bool isDownloadingInProgress = false;
  static Future<bool>? activeDownloadFuture;
  static Future<Directory> Function()? defaultTempDirProvider;

  static const MethodChannel _installerChannel =
      MethodChannel('com.cetaknota.app/installer');

  /// Helper mendapatkan direktori temporary/cache dengan fallback
  static Future<Directory> _getTempDirectory(
      Future<Directory> Function()? override) async {
    if (override != null) return await override();
    if (defaultTempDirProvider != null) return await defaultTempDirProvider!();
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  /// Hitung SHA-256 dari file lokal secara streaming
  static Future<String> _computeFileSha256(String filePath) async {
    final file = File(filePath);
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Pemicu instalasi file APK lokal ke sistem Android
  static Future<bool> triggerInstall(
    String filePath, {
    Future<bool> Function(String)? installer,
  }) async {
    if (installer != null) {
      return await installer(filePath);
    }
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _installerChannel.invokeMethod<bool>(
          'installApk',
          {'filePath': filePath},
        );
        return res ?? false;
      } catch (e) {
        debugPrint('Error triggering installer: $e');
        return false;
      }
    }
    return false;
  }

  /// Unduh APK di latar belakang dengan progress & verifikasi SHA-256
  static Future<bool> downloadApkBackground({
    required UpdateInfo updateInfo,
    http.Client? client,
    void Function(double progress)? onProgress,
    Future<Directory> Function()? tempDirProvider,
    Future<String> Function(String)? sha256Calculator,
  }) async {
    isDownloadingInProgress = true;
    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    final tempDir = await _getTempDirectory(tempDirProvider);

    final targetFile =
        File('${tempDir.path}/CetakNotaBT_v${updateInfo.versionCode}.apk');
    final partFile =
        File('${tempDir.path}/CetakNotaBT_v${updateInfo.versionCode}.part');

    // Hapus file part sebelumnya jika ada
    if (partFile.existsSync()) {
      try {
        partFile.deleteSync();
      } catch (_) {}
    }

    try {
      final request = http.Request('GET', Uri.parse(updateInfo.downloadUrl));
      request.headers['Cache-Control'] = 'no-cache';
      final response = await httpClient.send(request);

      if (response.statusCode != 200) {
        throw Exception('Server mengembalikan status ${response.statusCode}');
      }

      final totalBytes =
          response.contentLength ?? updateInfo.apkSizeBytes ?? 0;
      int receivedBytes = 0;
      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final p = (receivedBytes / totalBytes) * 100;
          currentUpdateInfo = currentUpdateInfo.copyWith(
            status: UpdateStatus.downloading,
            progress: p,
          );
          if (onProgress != null) onProgress(p);
        }
      }

      partFile.writeAsBytesSync(bytes);

      // Verifikasi SHA-256 Checksum
      if (updateInfo.apkChecksum != null &&
          updateInfo.apkChecksum!.trim().isNotEmpty) {
        final calcFn = sha256Calculator ?? _computeFileSha256;
        final computedChecksum = await calcFn(partFile.path);

        if (computedChecksum.toLowerCase() !=
            updateInfo.apkChecksum!.toLowerCase()) {
          // Checksum gagal: hapus file corrupt dan laporkan error
          if (partFile.existsSync()) {
            try {
              partFile.deleteSync();
            } catch (_) {}
          }
          currentUpdateInfo = currentUpdateInfo.copyWith(
            status: UpdateStatus.error,
            errorMessage:
                'File update rusak (checksum tidak cocok), coba lagi.',
          );
          return false;
        }
      }

      // Rename .part ke file final target
      if (targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
      partFile.renameSync(targetFile.path);

      currentUpdateInfo = currentUpdateInfo.copyWith(
        status: UpdateStatus.ready,
        progress: 100.0,
        localApkPath: targetFile.path,
      );
      return true;
    } catch (e) {
      if (partFile.existsSync()) {
        try {
          partFile.deleteSync();
        } catch (_) {}
      }
      currentUpdateInfo = currentUpdateInfo.copyWith(
        status: UpdateStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    } finally {
      isDownloadingInProgress = false;
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
  }

  /// Cek pembaruan aplikasi.
  static Future<UpdateInfo> checkUpdate(
    BuildContext context, {
    bool showNoUpdateToast = false,
    bool Function()? isSafe,
    http.Client? client,
    Future<int> Function()? getInstalledVersionCode,
    Future<String> Function()? getInstalledVersionName,
    SharedPreferences? testPrefs,
    String? customUrl,
    Future<Directory> Function()? tempDirProvider,
    Future<String> Function(String)? sha256Calculator,
    Future<bool> Function(String)? installer,
  }) async {
    currentUpdateInfo =
        currentUpdateInfo.copyWith(status: UpdateStatus.checking);
    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    try {
      final targetUrl = customUrl ?? versionJsonUrl;
      final uri =
          Uri.parse('$targetUrl?t=${DateTime.now().millisecondsSinceEpoch}');

      final response = await httpClient.get(
        uri,
        headers: {
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        currentUpdateInfo = currentUpdateInfo.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'Server mengembalikan status ${response.statusCode}',
        );
        if (showNoUpdateToast && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal memeriksa pembaruan server.')),
          );
        }
        return currentUpdateInfo;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final int serverVersionCode = data['version_code'] ?? 1;
      final String serverVersionName = data['version_name'] ?? '1.0.0';
      final String downloadUrl = data['download_url'] ?? '';
      final String changelog =
          data['changelog'] ?? 'Pembaruan fitur & perbaikan bug.';
      final bool forceUpdate = data['force_update'] ?? false;
      final int? apkSizeBytes = data['apk_size_bytes'] is int
          ? data['apk_size_bytes']
          : int.tryParse(data['apk_size_bytes']?.toString() ?? '');
      final String? apkChecksum = data['apk_checksum']?.toString();

      int currentBuildNumber = 1;
      String currentVersionName = '1.0.0';

      if (getInstalledVersionCode != null) {
        currentBuildNumber = await getInstalledVersionCode();
      } else {
        final packageInfo = await PackageInfo.fromPlatform();
        currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;
        currentVersionName = packageInfo.version;
      }

      if (getInstalledVersionName != null) {
        currentVersionName = await getInstalledVersionName();
      }

      if (serverVersionCode > currentBuildNumber && downloadUrl.isNotEmpty) {
        final prefs = testPrefs ?? await SharedPreferences.getInstance();
        final bool autoDownload =
            prefs.getBool('autoDownloadUpdate') ?? true;

        final tempDir = await _getTempDirectory(tempDirProvider);

        // Bersihkan file update versi lama di direktori temp
        try {
          final entities = tempDir.listSync();
          for (final entity in entities) {
            if (entity is File) {
              final name = entity.uri.pathSegments.last;
              if (name.startsWith('CetakNotaBT_') &&
                  !name.contains('v$serverVersionCode')) {
                try {
                  entity.deleteSync();
                } catch (_) {}
              }
            }
          }
        } catch (_) {}

        final targetFile =
            File('${tempDir.path}/CetakNotaBT_v$serverVersionCode.apk');
        bool hasReadyFile = false;

        if (targetFile.existsSync()) {
          if (apkChecksum != null && apkChecksum.isNotEmpty) {
            final calcFn = sha256Calculator ?? _computeFileSha256;
            final hash = await calcFn(targetFile.path);
            if (hash.toLowerCase() == apkChecksum.toLowerCase()) {
              hasReadyFile = true;
            } else {
              try {
                targetFile.deleteSync();
              } catch (_) {}
            }
          } else {
            hasReadyFile = true;
          }
        }

        final safeToApply = isSafe == null || isSafe();

        if (hasReadyFile) {
          // File update sudah tersedia & terverifikasi
          currentUpdateInfo = UpdateInfo(
            status: UpdateStatus.ready,
            versionCode: serverVersionCode,
            versionName: serverVersionName,
            downloadUrl: downloadUrl,
            changelog: changelog,
            forceUpdate: forceUpdate,
            apkSizeBytes: apkSizeBytes,
            apkChecksum: apkChecksum,
            progress: 100.0,
            localApkPath: targetFile.path,
          );

          if (safeToApply) {
            pendingUpdateInfo = null;
            if (context.mounted) {
              unawaited(_showUpdateDialog(
                context,
                updateInfo: currentUpdateInfo,
                testPrefs: testPrefs,
                installer: installer,
              ));
            }
          } else {
            pendingUpdateInfo = currentUpdateInfo;
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Pembaruan v$serverVersionName siap dipasang — akan ditawarkan di Beranda',
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        } else if (forceUpdate || !autoDownload) {
          // Force update atau auto-download dinonaktifkan: tampilkan dialog biasa
          currentUpdateInfo = UpdateInfo(
            status: UpdateStatus.available,
            versionCode: serverVersionCode,
            versionName: serverVersionName,
            downloadUrl: downloadUrl,
            changelog: changelog,
            forceUpdate: forceUpdate,
            apkSizeBytes: apkSizeBytes,
            apkChecksum: apkChecksum,
          );

          if (safeToApply) {
            pendingUpdateInfo = null;
            if (context.mounted) {
              unawaited(_showUpdateDialog(
                context,
                updateInfo: currentUpdateInfo,
                testPrefs: testPrefs,
                installer: installer,
              ));
            }
          } else {
            pendingUpdateInfo = currentUpdateInfo;
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Pembaruan v$serverVersionName tersedia — akan ditawarkan di Beranda',
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        } else {
          // Auto-download di background (Pola Buku Konter)
          currentUpdateInfo = UpdateInfo(
            status: UpdateStatus.downloading,
            versionCode: serverVersionCode,
            versionName: serverVersionName,
            downloadUrl: downloadUrl,
            changelog: changelog,
            forceUpdate: false,
            apkSizeBytes: apkSizeBytes,
            apkChecksum: apkChecksum,
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Mengunduh pembaruan v$serverVersionName di latar belakang...',
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }

          // Jalankan proses unduh background
          final downloadFuture = downloadApkBackground(
            updateInfo: currentUpdateInfo,
            client: client,
            tempDirProvider: tempDirProvider,
            sha256Calculator: sha256Calculator,
          );
          activeDownloadFuture = downloadFuture;
          downloadFuture.then((success) async {
            if (success) {
              final safeNow = isSafe == null || isSafe();
              if (safeNow && context.mounted) {
                pendingUpdateInfo = null;
                unawaited(_showUpdateDialog(
                  context,
                  updateInfo: currentUpdateInfo,
                  testPrefs: testPrefs,
                  installer: installer,
                ));
              } else {
                pendingUpdateInfo = currentUpdateInfo;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Pembaruan v$serverVersionName siap dipasang — akan ditawarkan di Beranda',
                      ),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            } else {
              if (context.mounted &&
                  currentUpdateInfo.errorMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(currentUpdateInfo.errorMessage!),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          });
        }
      } else {
        currentUpdateInfo =
            currentUpdateInfo.copyWith(status: UpdateStatus.none);
        pendingUpdateInfo = null;
        if (showNoUpdateToast && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Aplikasi Anda sudah versi terbaru (v$currentVersionName).',
              ),
            ),
          );
        }
      }
    } catch (e) {
      currentUpdateInfo = currentUpdateInfo.copyWith(
        status: UpdateStatus.error,
        errorMessage: e.toString(),
      );
      if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tidak dapat memeriksa pembaruan: $e')),
        );
      }
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }

    return currentUpdateInfo;
  }

  /// Tampilkan dialog update yang tertunda saat user kembali ke halaman Home
  static void showPendingUpdateDialog(
    BuildContext context, {
    SharedPreferences? testPrefs,
    Future<bool> Function(String)? installer,
  }) {
    if (pendingUpdateInfo != null && context.mounted) {
      final info = pendingUpdateInfo!;
      pendingUpdateInfo = null;
      _showUpdateDialog(
        context,
        updateInfo: info,
        testPrefs: testPrefs,
        installer: installer,
      );
    }
  }

  static Future<void> _showUpdateDialog(
    BuildContext context, {
    required UpdateInfo updateInfo,
    SharedPreferences? testPrefs,
    Future<bool> Function(String)? installer,
  }) async {
    // G-3: Muat preferensi hidePlayProtectNotice SEKALI di luar builder
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final bool initialNoticeHidden =
        prefs.getBool('hidePlayProtectNotice') ?? false;

    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (dialogContext) {
        double progress = updateInfo.progress;
        bool isDownloading = updateInfo.status == UpdateStatus.downloading;
        bool isReady = updateInfo.status == UpdateStatus.ready;
        String statusText = isReady ? 'Pembaruan siap dipasang' : '';
        String errorMsg = updateInfo.errorMessage ?? '';
        bool hideNoticeChecked = initialNoticeHidden;
        bool noticeHidden = initialNoticeHidden;

        final formattedSize = (updateInfo.apkSizeBytes != null &&
                updateInfo.apkSizeBytes! > 0)
            ? '${(updateInfo.apkSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB'
            : null;

        final shortChecksum = (updateInfo.apkChecksum != null &&
                updateInfo.apkChecksum!.isNotEmpty)
            ? 'SHA-256: ${updateInfo.apkChecksum!.substring(0, min(8, updateInfo.apkChecksum!.length))}…'
            : null;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return PopScope(
              canPop: !updateInfo.forceUpdate && !isDownloading,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: [
                    Icon(
                      isReady
                          ? Icons.check_circle_rounded
                          : Icons.system_update_rounded,
                      color: isReady ? Colors.green : Colors.indigo,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isReady ? 'Pembaruan Siap' : 'Pembaruan Tersedia',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Versi Terbaru: v${updateInfo.versionName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                          if (formattedSize != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                formattedSize,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (shortChecksum != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          shortChecksum,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (isReady) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.verified_rounded,
                                  color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'File update telah berhasil diunduh dan diverifikasi.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const Text(
                        'Catatan Perubahan:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          updateInfo.changelog,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),

                      // Play Protect Notice
                      if (!noticeHidden) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.security_rounded,
                                    size: 16,
                                    color: Colors.amber.shade900,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Pemberitahuan Pemasangan',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Aplikasi ini diinstal dari luar Play Store. Jika Play Protect menampilkan "Aplikasi berbahaya diblokir", aplikasi ini tetap aman karena ditandatangani sendiri oleh pengembang. Pilih "Detail selengkapnya" lalu "Tetap instal".',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.amber.shade900,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: hideNoticeChecked,
                                      activeColor: Colors.amber.shade900,
                                      onChanged: (val) async {
                                        setDialogState(() {
                                          hideNoticeChecked = val ?? false;
                                        });
                                        await prefs.setBool(
                                          'hidePlayProtectNotice',
                                          hideNoticeChecked,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      'Jangan tampilkan pesan ini lagi',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (isDownloading) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: progress > 0 ? progress / 100 : null,
                          backgroundColor: Colors.grey.shade200,
                          color: Colors.indigo,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                statusText,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (progress > 0)
                              Text(
                                '${progress.toInt()}%',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (errorMsg.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMsg,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  if (!isDownloading && !updateInfo.forceUpdate)
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text(
                        'Nanti',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  if (isReady)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        if (updateInfo.localApkPath != null) {
                          await triggerInstall(
                            updateInfo.localApkPath!,
                            installer: installer,
                          );
                        }
                      },
                      child: const Text(
                        'Pasang Sekarang',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  else if (!isDownloading)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        setDialogState(() {
                          isDownloading = true;
                          statusText = 'Mulai mengunduh...';
                          errorMsg = '';
                        });

                        try {
                          OtaUpdate()
                              .execute(
                            updateInfo.downloadUrl,
                            destinationFilename: 'CetakNotaBT.apk',
                            sha256checksum: updateInfo.apkChecksum,
                          )
                              .listen((OtaEvent event) {
                            setDialogState(() {
                              switch (event.status) {
                                case OtaStatus.DOWNLOADING:
                                  statusText = 'Mengunduh file...';
                                  progress =
                                      double.tryParse(event.value ?? '0') ?? 0;
                                  break;
                                case OtaStatus.INSTALLING:
                                  statusText = 'Memasang aplikasi...';
                                  break;
                                case OtaStatus.ALREADY_RUNNING_ERROR:
                                  statusText =
                                      'Proses unduh sedang berjalan...';
                                  break;
                                case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                                  isDownloading = false;
                                  errorMsg =
                                      'Izin menginstal aplikasi dari sumber luar ditolak.';
                                  break;
                                case OtaStatus.INTERNAL_ERROR:
                                case OtaStatus.DOWNLOAD_ERROR:
                                case OtaStatus.CHECKSUM_ERROR:
                                default:
                                  isDownloading = false;
                                  errorMsg =
                                      'Gagal mengunduh update: ${event.status} (${event.value})';
                                  break;
                              }
                            });
                          });
                        } catch (e) {
                          setDialogState(() {
                            isDownloading = false;
                            errorMsg = 'Terjadi kesalahan: $e';
                          });
                        }
                      },
                      child: const Text(
                        'Unduh & Pasang',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
