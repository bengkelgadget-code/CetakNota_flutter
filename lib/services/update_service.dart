import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/bengkelgadget-code/CetakNota_flutter/main/version.json';

  static Future<void> checkUpdate(BuildContext context,
      {bool showNoUpdateToast = false}) async {
    try {
      final response = await http.get(Uri.parse(versionJsonUrl)).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) {
        if (showNoUpdateToast && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal memeriksa pembaruan server.')),
          );
        }
        return;
      }

      final data = jsonDecode(response.body);
      final int serverVersionCode = data['version_code'] ?? 1;
      final String serverVersionName = data['version_name'] ?? '1.0.0';
      final String downloadUrl = data['download_url'] ?? '';
      final String changelog = data['changelog'] ?? 'Pembaruan fitur & perbaikan bug.';
      final bool forceUpdate = data['force_update'] ?? false;

      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final int currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 1;

      if (serverVersionCode > currentBuildNumber && downloadUrl.isNotEmpty) {
        if (context.mounted) {
          _showUpdateDialog(
            context,
            serverVersionName: serverVersionName,
            downloadUrl: downloadUrl,
            changelog: changelog,
            forceUpdate: forceUpdate,
          );
        }
      } else {
        if (showNoUpdateToast && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Aplikasi Anda sudah versi terbaru (v${packageInfo.version}).'),
            ),
          );
        }
      }
    } catch (e) {
      if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tidak dapat memeriksa pembaruan: $e')),
        );
      }
    }
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String serverVersionName,
    required String downloadUrl,
    required String changelog,
    required bool forceUpdate,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (ctx) {
        double progress = 0;
        bool isDownloading = false;
        String statusText = '';
        String errorMsg = '';

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return PopScope(
              canPop: !forceUpdate && !isDownloading,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: const [
                    Icon(Icons.system_update_rounded, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('Pembaruan Tersedia',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versi Terbaru: v$serverVersionName',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                    const SizedBox(height: 8),
                    const Text('Catatan Perubahan:',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        changelog,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
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
                                  fontSize: 11, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (progress > 0)
                            Text(
                              '${progress.toInt()}%',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo),
                            ),
                        ],
                      ),
                    ],
                    if (errorMsg.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMsg,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ],
                  ],
                ),
                actions: [
                  if (!isDownloading && !forceUpdate)
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Nanti',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  if (!isDownloading)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        setDialogState(() {
                          isDownloading = true;
                          statusText = 'Mulai mengunduh...';
                          errorMsg = '';
                        });

                        try {
                          OtaUpdate()
                              .execute(downloadUrl,
                                  destinationFilename: 'CetakNotaBT.apk')
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
                                  statusText = 'Proses unduh sedang berjalan...';
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
                      child: const Text('Update Sekarang',
                          style: TextStyle(color: Colors.white)),
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
