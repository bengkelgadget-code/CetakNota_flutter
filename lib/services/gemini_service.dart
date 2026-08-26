import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static Future<Map<String, dynamic>?> processReceipt(
      String base64Data, String type, String apiKey, {String mimeType = "image/jpeg"}) async {
    
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
                "data": base64Data
              }
            }
          ]
        }
      ]
    };

    final models = ['gemini-2.5-flash', 'gemini-3.5-flash', 'gemini-3.6-flash'];
    String lastError = '';
    
    for (String model in models) {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');
          
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

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
          lastError = 'Format salah dari $model: $textResponse';
          continue; // coba model lain
        }
      } else {
        lastError = 'API Gemini ($model) menolak (Code: ${response.statusCode}). Detail: ${response.body}';
        continue; // coba model lain
      }
    }
    
    throw Exception(lastError);
  }
}
