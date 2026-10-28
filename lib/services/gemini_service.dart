import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static Future<Map<String, dynamic>?> processReceipt(
    String base64Data,
    String type,
    String apiKey, {
    String mimeType = "image/jpeg",
    void Function(String status)? onStatus,
  }) async {
    final prompt = type == 'Transfer'
        ? "Ekstrak informasi dari struk bukti transfer berikut. KEMBALIKAN HANYA FORMAT JSON MURNI TANPA MARKDOWN ATAU TEKS LAIN. Field yang diperlukan: referensi (jika ada), nama_penerima, bank_tujuan, rekening_tujuan, nominal, admin (jika ada, jika tidak ada isikan 0), tanggal, waktu."
        : "Ekstrak informasi dari struk token listrik berikut. KEMBALIKAN HANYA FORMAT JSON MURNI TANPA MARKDOWN ATAU TEKS LAIN. Field yang diperlukan: no_meter, id_pel (jika ada), nama, tarif_daya, kwh, token (pastikan angka token lengkap 20 digit), nominal, admin (jika ada), tanggal, waktu, sn (jika ada).";

    final body = {
      "contents": [
        {
          "parts": [
            {"text": prompt},
            {
              "inline_data": {
                "mime_type": mimeType,
                "data": base64Data,
              }
            }
          ]
        }
      ]
    };

    // Daftar model yang 100% terbukti aktif dan cepat untuk akun ini
    final models = [
      'gemini-3.5-flash',
      'gemini-3.6-flash',
    ];

    List<String> failedLogs = [];

    for (int i = 0; i < models.length; i++) {
      final model = models[i];
      if (i > 0 && onStatus != null) {
        onStatus('Mencoba server cadangan ($model)...');
      }

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
      );

      // Coba request dengan retry jika terkena rate limit (429)
      for (int attempt = 0; attempt < 2; attempt++) {
        http.Response response;
        try {
          response = await http
              .post(
                url,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 30));
        } catch (e) {
          failedLogs.add('$model: Gagal koneksi ($e)');
          break; // pindah ke model berikutnya jika timeout/jaringan
        }

        if (response.statusCode == 200) {
          final jsonResponse = jsonDecode(response.body);
          final String textResponse =
              jsonResponse['candidates'][0]['content']['parts'][0]['text'];

          String cleanJson = textResponse;
          if (textResponse.contains('```json')) {
            cleanJson = textResponse.split('```json')[1].split('```')[0].trim();
          } else if (textResponse.contains('```')) {
            cleanJson = textResponse.split('```')[1].split('```')[0].trim();
          } else {
            int start = textResponse.indexOf('{');
            int end = textResponse.lastIndexOf('}');
            if (start != -1 && end != -1 && end > start) {
              cleanJson = textResponse.substring(start, end + 1).trim();
            }
          }

          try {
            return jsonDecode(cleanJson) as Map<String, dynamic>;
          } catch (e) {
            failedLogs.add('$model: Format JSON tidak sesuai ($e)');
            break; // coba model lain
          }
        }

        // Jika masalah autentikasi atau API Key salah, langsung hentikan
        if (response.statusCode == 400 || response.statusCode == 401 || response.statusCode == 403) {
          try {
            final errBody = jsonDecode(response.body);
            final msg = errBody['error']?['message'] ?? response.body;
            throw Exception('API Key Gemini ditolak ($msg). Periksa API Key di menu Pengaturan.');
          } catch (e) {
            if (e is Exception && e.toString().contains('API Key')) rethrow;
            throw Exception('API Key Gemini tidak valid (Code: ${response.statusCode}). Periksa di Pengaturan.');
          }
        }

        // Jika terkena Rate Limit (429) atau Server Sibuk (503), tunggu 2 detik lalu retry sekali
        if (response.statusCode == 429 || response.statusCode == 503) {
          if (attempt == 0) {
            if (onStatus != null) {
              onStatus('Server $model padat, mencoba ulang...');
            }
            await Future.delayed(const Duration(milliseconds: 2000));
            continue; // coba lagi sekali di model yang sama
          }
          failedLogs.add('$model: Kuota/Rate limit penuh (Code: ${response.statusCode})');
          break; // lanjut coba model cadangan berikutnya
        }

        // Jika 404 (model tidak didukung), catat lalu coba model berikutnya
        failedLogs.add('$model: Ditolak (Code: ${response.statusCode})');
        break; // coba model berikutnya
      }
    }

    throw Exception(failedLogs.isNotEmpty ? failedLogs.join('\n') : 'Gagal memproses struk.');
  }
}
