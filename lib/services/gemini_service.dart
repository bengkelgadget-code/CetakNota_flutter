import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static const List<String> models = [
    'gemini-3.5-flash-lite', // UTAMA — paling cepat untuk OCR/ekstrak struk
    'gemini-3.8-flash', // CADANGAN 1 — kalau Lite gagal baca (struk buram / token tidak lengkap)
    'gemini-4-hydrogen', // CADANGAN 2 — hanya untuk kasus sulit, JANGAN jadi utama
  ];

  static Map<String, dynamic> getTransferSchema() {
    return {
      "type": "OBJECT",
      "properties": {
        "referensi": {"type": "STRING"},
        "nama_penerima": {"type": "STRING"},
        "bank_tujuan": {"type": "STRING"},
        "rekening_tujuan": {"type": "STRING"},
        "nominal": {
          "type": "INTEGER",
          "description":
              "Nominal transfer sebagai angka, tanpa Rp dan tanpa pemisah ribuan",
        },
        "admin": {
          "type": "INTEGER",
          "description":
              "Biaya admin sebagai angka; 0 bila tidak ada di struk",
        },
        "tanggal": {"type": "STRING"},
        "waktu": {"type": "STRING"},
      },
      "required": [
        "nama_penerima",
        "bank_tujuan",
        "rekening_tujuan",
        "nominal",
        "tanggal",
        "waktu",
      ],
    };
  }

  static Map<String, dynamic> getTokenSchema() {
    return {
      "type": "OBJECT",
      "properties": {
        "no_meter": {"type": "STRING"},
        "id_pel": {"type": "STRING"},
        "nama": {"type": "STRING"},
        "tarif_daya": {"type": "STRING"},
        "kwh": {"type": "STRING"},
        "token": {
          "type": "STRING",
          "description":
              "Kode token listrik, HARUS tepat 20 digit angka, tanpa spasi dan tanpa strip",
        },
        "nominal": {
          "type": "INTEGER",
          "description":
              "Nominal sebagai angka, tanpa Rp dan tanpa pemisah ribuan",
        },
        "admin": {
          "type": "INTEGER",
          "description":
              "Biaya admin sebagai angka; 0 bila tidak ada di struk",
        },
        "tanggal": {"type": "STRING"},
        "waktu": {"type": "STRING"},
        "sn": {"type": "STRING"},
      },
      "required": [
        "no_meter",
        "nama",
        "token",
        "nominal",
        "tanggal",
        "waktu",
      ],
    };
  }

  static Map<String, dynamic> buildRequestBody({
    required String prompt,
    required String mimeType,
    required String base64Data,
    required Map<String, dynamic> schema,
    String? thinkingLevel,
  }) {
    final generationConfig = <String, dynamic>{
      "responseMimeType": "application/json",
      "responseJsonSchema": schema,
      "maxOutputTokens": 1024,
    };

    if (thinkingLevel != null) {
      generationConfig["thinkingConfig"] = {
        "thinkingLevel": thinkingLevel,
      };
    }

    return {
      "contents": [
        {
          "parts": [
            {"text": prompt},
            {
              "inline_data": {
                "mime_type": mimeType,
                "data": base64Data,
              },
            },
          ],
        },
      ],
      "generationConfig": generationConfig,
    };
  }

  static Future<Map<String, dynamic>?> processReceipt(
    String base64Data,
    String type,
    String apiKey, {
    String mimeType = "image/jpeg",
    void Function(String status)? onStatus,
    http.Client? client,
    Duration? mainTimeout,
    Duration? fallbackTimeout,
    Duration? totalTimeout,
    Duration? retryDelay,
  }) async {
    const prompt =
        "Ekstrak data dari struk ini sesuai schema. Angka tanpa 'Rp', tanpa titik ribuan, tanpa spasi.";

    final schema = type == 'Transfer' ? getTransferSchema() : getTokenSchema();
    final effectiveMainTimeout = mainTimeout ?? const Duration(seconds: 15);
    final effectiveFallbackTimeout =
        fallbackTimeout ?? const Duration(seconds: 20);
    final effectiveTotalTimeout = totalTimeout ?? const Duration(seconds: 60);
    final effectiveRetryDelay = retryDelay ?? const Duration(seconds: 1);

    final httpClient = client ?? http.Client();
    final shouldCloseClient = client == null;

    final stopwatch = Stopwatch()..start();
    final List<String> failedLogs = [];

    try {
      for (int i = 0; i < models.length; i++) {
        if (stopwatch.elapsed >= effectiveTotalTimeout) {
          failedLogs.add(
            'Batas waktu total (${effectiveTotalTimeout.inSeconds} detik) terlampaui',
          );
          break;
        }

        final model = models[i];
        final isMainModel = (i == 0);
        final timeout =
            isMainModel ? effectiveMainTimeout : effectiveFallbackTimeout;
        final maxAttempts = isMainModel ? 2 : 1;

        if (onStatus != null) {
          if (i == 0) {
            onStatus('Memindai struk…');
          } else if (i == 1) {
            onStatus('Flash-Lite lambat, mencoba server cadangan (3.8 Flash)…');
          } else {
            onStatus('Mencoba server cadangan terakhir (Hydrogen)…');
          }
        }

        final String thinkingLevel =
            (model == 'gemini-3.5-flash-lite') ? 'MINIMAL' : 'LOW';
        bool includeThinking = true;

        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
        );

        for (int attempt = 0; attempt < maxAttempts; attempt++) {
          if (stopwatch.elapsed >= effectiveTotalTimeout) {
            failedLogs.add(
              '$model: Waktu habis sebelum percobaan ke-${attempt + 1}',
            );
            break;
          }

          final body = buildRequestBody(
            prompt: prompt,
            mimeType: mimeType,
            base64Data: base64Data,
            schema: schema,
            thinkingLevel: includeThinking ? thinkingLevel : null,
          );

          http.Response response;
          try {
            response = await httpClient
                .post(
                  url,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(body),
                )
                .timeout(timeout);
          } on TimeoutException {
            failedLogs.add('$model: Timeout ${timeout.inSeconds} detik');
            break; // Timeout -> lanjut ke model berikutnya
          } catch (e) {
            failedLogs.add('$model: Gagal koneksi ($e)');
            break; // Network error -> lanjut ke model berikutnya
          }

          if (response.statusCode == 200) {
            try {
              final jsonResponse = jsonDecode(response.body);
              final String textResponse =
                  jsonResponse['candidates'][0]['content']['parts'][0]['text'];

              String cleanJson = textResponse;
              if (textResponse.contains('```json')) {
                cleanJson =
                    textResponse.split('```json')[1].split('```')[0].trim();
              } else if (textResponse.contains('```')) {
                cleanJson =
                    textResponse.split('```')[1].split('```')[0].trim();
              } else {
                int start = textResponse.indexOf('{');
                int end = textResponse.lastIndexOf('}');
                if (start != -1 && end != -1 && end > start) {
                  cleanJson = textResponse.substring(start, end + 1).trim();
                }
              }

              final parsed = jsonDecode(cleanJson) as Map<String, dynamic>;
              return parsed;
            } catch (e) {
              failedLogs.add('$model: Format JSON tidak sesuai ($e)');
              break; // JSON parse error: JANGAN retry model yang sama, lanjut ke model berikutnya
            }
          }

          // Cek apakah 400 karena thinkingConfig ditolak server
          if (response.statusCode == 400 && includeThinking) {
            final bodyLower = response.body.toLowerCase();
            if (bodyLower.contains('thinkingconfig') ||
                bodyLower.contains('thinkinglevel') ||
                bodyLower.contains('thinking_config')) {
              failedLogs.add(
                '$model: thinkingConfig ditolak, mencoba ulang tanpa thinkingConfig',
              );
              includeThinking = false;
              // Ulangi request yang sama tanpa thinkingConfig
              continue;
            }
          }

          // Auth error (400 / 401 / 403)
          if (response.statusCode == 400 ||
              response.statusCode == 401 ||
              response.statusCode == 403) {
            try {
              final errBody = jsonDecode(response.body);
              final msg = errBody['error']?['message'] ?? response.body;
              throw Exception(
                'API Key Gemini ditolak ($msg). Periksa API Key di menu Pengaturan.',
              );
            } catch (e) {
              if (e is Exception && e.toString().contains('API Key')) rethrow;
              throw Exception(
                'API Key Gemini tidak valid (Code: ${response.statusCode}). Periksa di Pengaturan.',
              );
            }
          }

          // Rate limit 429 atau 503
          if (response.statusCode == 429 || response.statusCode == 503) {
            if (isMainModel && attempt == 0) {
              failedLogs.add(
                '$model: Server padat (Code: ${response.statusCode}), retry dalam ${effectiveRetryDelay.inSeconds} detik',
              );
              await Future.delayed(effectiveRetryDelay);
              continue; // retry 1x untuk model utama
            } else {
              failedLogs.add(
                '$model: Kuota/Rate limit penuh (Code: ${response.statusCode})',
              );
              break; // cadangan atau percobaan ke-2: lanjut ke model berikutnya
            }
          }

          // Error lainnya (404 dsb)
          failedLogs.add('$model: Ditolak (Code: ${response.statusCode})');
          break;
        }
      }
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }

    throw Exception(
      failedLogs.isNotEmpty
          ? 'Gagal memproses struk:\n${failedLogs.join('\n')}'
          : 'Gagal memproses struk.',
    );
  }
}
