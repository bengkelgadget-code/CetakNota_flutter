import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
    );
  }
}

class UpdateService {
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/bengkelgadget-code/CetakNota_flutter/main/version.json';

  static UpdateInfo currentUpdateInfo = const UpdateInfo();
  static UpdateInfo? pendingUpdateInfo;

  /// Cek pembaruan aplikasi.
  /// Mendukung inject client & version reader untuk unit test.
  static Future<UpdateInfo> checkUpdate(
    BuildContext context, {
    bool showNoUpdateToast = false,
    bool Function()? isSafe,
    http.Client? client,
    Future<int> Function()? getInstalledVersionCode,
    Future<String> Function()? getInstalledVersionName,
    SharedPreferences? testPrefs,
    String? customUrl,
  }) async {
    currentUpdateInfo = currentUpdateInfo.copyWith(status: UpdateStatus.checking);
    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    try {
      final targetUrl = customUrl ?? versionJsonUrl;
      final uri = Uri.parse('$targetUrl?t=${DateTime.now().millisecondsSinceEpoch}');

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

        final safeToApply = isSafe == null || isSafe();

        if (safeToApply) {
          pendingUpdateInfo = null;
          if (context.mounted) {
            _showUpdateDialog(
              context,
              updateInfo: currentUpdateInfo,
              testPrefs: testPrefs,
            );
          }
        } else {
          // Pola Buku Konter: Simpan pending dan tampilkan toast singkat 4 detik
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
        currentUpdateInfo = currentUpdateInfo.copyWith(status: UpdateStatus.none);
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
  static void showPendingUpdateDialog(BuildContext context) {
    if (pendingUpdateInfo != null && context.mounted) {
      final info = pendingUpdateInfo!;
      pendingUpdateInfo = null;
      _showUpdateDialog(context, updateInfo: info);
    }
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required UpdateInfo updateInfo,
    SharedPreferences? testPrefs,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (ctx) {
        double progress = 0;
        bool isDownloading = false;
        String statusText = '';
        String errorMsg = '';
        bool hideNoticeChecked = false;
        bool noticeHidden = false;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // Muat status hidePlayProtectNotice
            if (!isDownloading && statusText.isEmpty) {
              if (testPrefs != null) {
                noticeHidden = testPrefs.getBool('hidePlayProtectNotice') ?? false;
              } else {
                SharedPreferences.getInstance().then((prefs) {
                  final hidden = prefs.getBool('hidePlayProtectNotice') ?? false;
                  if (hidden != noticeHidden) {
                    setDialogState(() {
                      noticeHidden = hidden;
                    });
                  }
                });
              }
            }

            final formattedSize = (updateInfo.apkSizeBytes != null &&
                    updateInfo.apkSizeBytes! > 0)
                ? '${(updateInfo.apkSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB'
                : null;

            final shortChecksum = (updateInfo.apkChecksum != null &&
                    updateInfo.apkChecksum!.isNotEmpty)
                ? 'SHA-256: ${updateInfo.apkChecksum!.substring(0, min(8, updateInfo.apkChecksum!.length))}…'
                : null;

            return PopScope(
              canPop: !updateInfo.forceUpdate && !isDownloading,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: const [
                    Icon(Icons.system_update_rounded, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text(
                      'Pembaruan Tersedia',
                      style: TextStyle(
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

                      // Play Protect Notice (sesuai Buku Konter BG-VUE3)
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
                                        final prefs = testPrefs ??
                                            await SharedPreferences.getInstance();
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
                  if (!isDownloading)
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
