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

    if (thinkingLevel != null && thinkingLevel.isNotEmpty) {
      generationConfig["thinkingConfig"] = {"thinkingLevel": thinkingLevel};
    }

    return {
      "contents": [
        {
          "parts": [
            {"text": prompt},
            {
              "inline_data": {"mime_type": mimeType, "data": base64Data},
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
        final remainingTotalBeforeModel =
            effectiveTotalTimeout - stopwatch.elapsed;
        if (remainingTotalBeforeModel <= Duration.zero) {
          failedLogs.add(
            'Batas waktu total (${effectiveTotalTimeout.inSeconds} detik) terlampaui',
          );
          break;
        }

        final model = models[i];
        final isMainModel = (i == 0);
        final baseTimeout =
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

        int attempt = 0;
        while (attempt < maxAttempts) {
          final remainingTotal = effectiveTotalTimeout - stopwatch.elapsed;
          if (remainingTotal <= Duration.zero) {
            failedLogs.add(
              '$model: Waktu habis sebelum percobaan ke-${attempt + 1}',
            );
            break;
          }

          final effectiveTimeout =
              baseTimeout < remainingTotal ? baseTimeout : remainingTotal;

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
                .timeout(effectiveTimeout);
          } on TimeoutException {
            failedLogs.add(
              '$model: Timeout ${effectiveTimeout.inSeconds} detik',
            );
            break; // Timeout -> lanjut ke model berikutnya
          } catch (e) {
            failedLogs.add('$model: Gagal koneksi ($e)');
            break; // Network error -> lanjut ke model berikutnya
          }

          // B-F3: Validasi struktur respons 200 secara aman tanpa masking error
          if (response.statusCode == 200) {
            Map<String, dynamic> jsonResponse;
            try {
              jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
            } catch (e) {
              failedLogs.add('$model: Gagal decode body JSON ($e)');
              break;
            }

            final candidates = jsonResponse['candidates'] as List?;
            if (candidates == null || candidates.isEmpty) {
              final promptFeedback = jsonResponse['promptFeedback'];
              final blockReason = promptFeedback?['blockReason'];
              final reasonStr =
                  blockReason != null ? ' (blockReason: $blockReason)' : '';
              failedLogs.add('$model: Respons 200 tanpa candidates$reasonStr');
              break;
            }

            final firstCandidate = candidates[0] as Map<String, dynamic>?;
            final finishReason = firstCandidate?['finishReason'];
            final parts = firstCandidate?['content']?['parts'] as List?;

            if (parts == null || parts.isEmpty) {
              final reasonStr =
                  finishReason != null ? ' (finishReason: $finishReason)' : '';
              failedLogs.add(
                '$model: Respons 200 tanpa content parts$reasonStr',
              );
              break;
            }

            final textResponse = parts[0]['text'] as String?;
            if (textResponse == null || textResponse.trim().isEmpty) {
              final reasonStr =
                  finishReason != null ? ' (finishReason: $finishReason)' : '';
              failedLogs.add('$model: Respons 200 tanpa teks$reasonStr');
              break;
            }

            try {
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

          // B-F1: Cek apakah 400 karena thinkingConfig ditolak server (tanpa menghabiskan jatah attempt)
          if (response.statusCode == 400 && includeThinking) {
            final bodyLower = response.body.toLowerCase();
            if (bodyLower.contains('thinkingconfig') ||
                bodyLower.contains('thinkinglevel') ||
                bodyLower.contains('thinking_config')) {
              failedLogs.add(
                '$model: thinkingConfig ditolak, mencoba ulang tanpa thinkingConfig',
              );
              includeThinking = false;
              // Ulangi request ini tanpa thinkingConfig pada attempt yang sama
              continue;
            }
          }

          // B-F2: Cek 400 karena schema JSON ditolak server
          if (response.statusCode == 400) {
            final bodyLower = response.body.toLowerCase();
            if (bodyLower.contains('schema') ||
                bodyLower.contains('responsejsonschema') ||
                bodyLower.contains('invalid argument') ||
                bodyLower.contains('invalid_argument')) {
              String detail = response.body;
              try {
                final errJson = jsonDecode(response.body);
                detail = errJson['error']?['message'] ?? response.body;
              } catch (_) {}
              final errorMsg =
                  'Schema JSON ditolak server ($detail). Periksa responseJsonSchema di GeminiService.';
              failedLogs.add('$model: $errorMsg');
              throw Exception(errorMsg);
            }
          }

          // Auth error: 401, 403, atau 400 yang pesannya eksplisit menyebut API key / auth
          if (response.statusCode == 401 || response.statusCode == 403) {
            String msg = response.body;
            try {
              final errBody = jsonDecode(response.body);
              msg = errBody['error']?['message'] ?? response.body;
            } catch (_) {}
            throw Exception(
              'API Key Gemini ditolak ($msg). Periksa API Key di menu Pengaturan.',
            );
          }

          if (response.statusCode == 400) {
            final bodyLower = response.body.toLowerCase();
            if (bodyLower.contains('api key') ||
                bodyLower.contains('apikey') ||
                bodyLower.contains('auth') ||
                bodyLower.contains('credential')) {
              String msg = response.body;
              try {
                final errBody = jsonDecode(response.body);
                msg = errBody['error']?['message'] ?? response.body;
              } catch (_) {}
              throw Exception(
                'API Key Gemini ditolak ($msg). Periksa API Key di menu Pengaturan.',
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
              attempt++;
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
