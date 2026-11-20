import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scanner_nota_flutter/services/gemini_service.dart';

void main() {
  group('GeminiService Unit Tests', () {
    test('1. Valid Transfer JSON response returns expected fields and parsed types', () async {
      final mockClient = MockClient((request) async {
        final responsePayload = {
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": jsonEncode({
                      "referensi": "TRX12345678",
                      "nama_penerima": "Budi Santoso",
                      "bank_tujuan": "BCA",
                      "rekening_tujuan": "1234567890",
                      "nominal": 500000,
                      "admin": 0,
                      "tanggal": "20/11/2026",
                      "waktu": "10:30",
                    }),
                  }
                ],
              },
            }
          ],
        };
        return http.Response(jsonEncode(responsePayload), 200);
      });

      final result = await GeminiService.processReceipt(
        "dummy_base64",
        "Transfer",
        "test_api_key",
        client: mockClient,
      );

      expect(result, isNotNull);
      expect(result!['referensi'], 'TRX12345678');
      expect(result['nama_penerima'], 'Budi Santoso');
      expect(result['bank_tujuan'], 'BCA');
      expect(result['rekening_tujuan'], '1234567890');
      expect(result['nominal'], 500000);
      expect(result['admin'], 0);
      expect(result['tanggal'], '20/11/2026');
      expect(result['waktu'], '10:30');
    });

    test('2. Valid Token JSON with 20-digit token passes intact without spaces/hyphens', () async {
      final mockClient = MockClient((request) async {
        final responsePayload = {
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": jsonEncode({
                      "no_meter": "14234567890",
                      "id_pel": "531234567890",
                      "nama": "Ahmad Fauzi",
                      "tarif_daya": "R1/1300VA",
                      "kwh": "65.4",
                      "token": "12345678901234567890",
                      "nominal": 100000,
                      "admin": 2500,
                      "tanggal": "20/11/2026",
                      "waktu": "14:15",
                      "sn": "PLN987654321",
                    }),
                  }
                ],
              },
            }
          ],
        };
        return http.Response(jsonEncode(responsePayload), 200);
      });

      final result = await GeminiService.processReceipt(
        "dummy_base64",
        "Token",
        "test_api_key",
        client: mockClient,
      );

      expect(result, isNotNull);
      expect(result!['token'], '12345678901234567890');
      expect(result['token'].toString().length, 20);
      expect(result['token'].toString().contains(' '), isFalse);
      expect(result['token'].toString().contains('-'), isFalse);
      expect(result['nominal'], 100000);
      expect(result['admin'], 2500);
    });

    test('3. Markdown fence json format parses correctly via fallback', () async {
      final mockClient = MockClient((request) async {
        const rawJsonWithMarkdown = """
```json
{
  "nama_penerima": "Siti Nurhaliza",
  "bank_tujuan": "BRI",
  "rekening_tujuan": "9876543210",
  "nominal": 250000,
  "admin": 0,
  "tanggal": "20/11/2026",
  "waktu": "09:00"
}
```
""";
        final responsePayload = {
          "candidates": [
            {
              "content": {
                "parts": [
                  {"text": rawJsonWithMarkdown}
                ],
              },
            }
          ],
        };
        return http.Response(jsonEncode(responsePayload), 200);
      });

      final result = await GeminiService.processReceipt(
        "dummy_base64",
        "Transfer",
        "test_api_key",
        client: mockClient,
      );

      expect(result, isNotNull);
      expect(result!['nama_penerima'], 'Siti Nurhaliza');
      expect(result['bank_tujuan'], 'BRI');
      expect(result['nominal'], 250000);
    });

    test('4. Lite 429 retries 1x after delay then succeeds; 429 twice moves to 3.8 Flash', () async {
      int requestCount = 0;
      final requestedUrls = <String>[];

      // Skenario A: 429 sekali, lalu sukses di percobaan kedua
      final mockClientA = MockClient((request) async {
        requestCount++;
        requestedUrls.add(request.url.path);
        if (requestCount == 1) {
          return http.Response('{"error": {"code": 429, "message": "Resource exhausted"}}', 429);
        }
        return http.Response(jsonEncode({
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": jsonEncode({
                      "nama_penerima": "Budi",
                      "bank_tujuan": "BCA",
                      "rekening_tujuan": "123",
                      "nominal": 50000,
                      "admin": 0,
                      "tanggal": "20/11/2026",
                      "waktu": "10:00"
                    })
                  }
                ]
              }
            }
          ]
        }), 200);
      });

      final resultA = await GeminiService.processReceipt(
        "dummy_base64",
        "Transfer",
        "test_api_key",
        client: mockClientA,
        retryDelay: const Duration(milliseconds: 10), // cepat untuk tes
      );

      expect(resultA, isNotNull);
      expect(requestCount, 2);
      expect(requestedUrls[0], contains('gemini-3.5-flash-lite'));
      expect(requestedUrls[1], contains('gemini-3.5-flash-lite'));

      // Skenario B: 429 dua kali pada Lite -> harus pindah ke 3.8 Flash (bukan retry Lite ke-3)
      final requestedUrlsB = <String>[];
      final mockClientB = MockClient((request) async {
        requestedUrlsB.add(request.url.path);
        if (request.url.path.contains('gemini-3.5-flash-lite')) {
          return http.Response('{"error": {"code": 429}}', 429);
        }
        if (request.url.path.contains('gemini-3.8-flash')) {
          return http.Response(jsonEncode({
            "candidates": [
              {
                "content": {
                  "parts": [
                    {
                      "text": jsonEncode({
                        "nama_penerima": "Eko",
                        "bank_tujuan": "Mandiri",
                        "rekening_tujuan": "456",
                        "nominal": 75000,
                        "admin": 0,
                        "tanggal": "20/11/2026",
                        "waktu": "11:00"
                      })
                    }
                  ]
                }
              }
            ]
          }), 200);
        }
        return http.Response('Not found', 404);
      });

      final resultB = await GeminiService.processReceipt(
        "dummy_base64",
        "Transfer",
        "test_api_key",
        client: mockClientB,
        retryDelay: const Duration(milliseconds: 10),
      );

      expect(resultB, isNotNull);
      expect(requestedUrlsB.length, 3);
      expect(requestedUrlsB[0], contains('gemini-3.5-flash-lite'));
      expect(requestedUrlsB[1], contains('gemini-3.5-flash-lite'));
      expect(requestedUrlsB[2], contains('gemini-3.8-flash'));
    });

    test('5. Lite timeout records in failedLogs and proceeds to next model without hanging', () async {
      final requestedUrls = <String>[];
      final mockClient = MockClient((request) async {
        requestedUrls.add(request.url.path);
        if (request.url.path.contains('gemini-3.5-flash-lite')) {
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response('{"error": "timeout"}', 504);
        }
        return http.Response(jsonEncode({
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": jsonEncode({
                      "nama_penerima": "Dewi",
                      "bank_tujuan": "BNI",
                      "rekening_tujuan": "789",
                      "nominal": 120000,
                      "admin": 0,
                      "tanggal": "20/11/2026",
                      "waktu": "12:00"
                    })
                  }
                ]
              }
            }
          ]
        }), 200);
      });

      final result = await GeminiService.processReceipt(
        "dummy_base64",
        "Transfer",
        "test_api_key",
        client: mockClient,
        mainTimeout: const Duration(milliseconds: 20), // timeout pendek untuk tes
      );

      expect(result, isNotNull);
      expect(requestedUrls.length, 2);
      expect(requestedUrls[0], contains('gemini-3.5-flash-lite'));
      expect(requestedUrls[1], contains('gemini-3.8-flash'));
    });

    test('6. All models fail (429/503/404) -> final error mentions all tried models and codes', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('gemini-3.5-flash-lite')) {
          return http.Response('{"error": "Resource exhausted"}', 429);
        } else if (request.url.path.contains('gemini-3.8-flash')) {
          return http.Response('{"error": "Overloaded"}', 503);
        } else {
          return http.Response('{"error": "Not found"}', 404);
        }
      });

      expect(
        () => GeminiService.processReceipt(
          "dummy_base64",
          "Transfer",
          "test_api_key",
          client: mockClient,
          retryDelay: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf([
              contains('gemini-3.5-flash-lite'),
              contains('gemini-3.8-flash'),
              contains('gemini-4-hydrogen'),
              contains('429'),
              contains('503'),
              contains('404'),
            ]),
          ),
        ),
      );
    });

    test('7. Schema test: generationConfig sent has responseMimeType, schema, maxOutputTokens, and thinkingLevel', () async {
      final capturedBodies = <Map<String, dynamic>>[];

      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedBodies.add(body);

        if (request.url.path.contains('gemini-3.5-flash-lite')) {
          return http.Response('{"error": "rate limit"}', 429);
        } else if (request.url.path.contains('gemini-3.8-flash')) {
          return http.Response('{"error": "rate limit"}', 429);
        }
        return http.Response(jsonEncode({
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": jsonEncode({
                      "no_meter": "111",
                      "nama": "Test",
                      "token": "11112222333344445555",
                      "nominal": 20000,
                      "admin": 0,
                      "tanggal": "20/11/2026",
                      "waktu": "12:00"
                    })
                  }
                ]
              }
            }
          ]
        }), 200);
      });

      await GeminiService.processReceipt(
        "dummy_base64",
        "Token",
        "test_api_key",
        client: mockClient,
        retryDelay: const Duration(milliseconds: 10),
      );

      // capturedBodies[0]: Lite attempt 1
      expect(capturedBodies[0]['generationConfig']['responseMimeType'], 'application/json');
      expect(capturedBodies[0]['generationConfig']['maxOutputTokens'], 1024);
      expect(capturedBodies[0]['generationConfig']['thinkingConfig']['thinkingLevel'], 'MINIMAL');
      expect(capturedBodies[0]['generationConfig']['responseJsonSchema']['properties'], contains('token'));

      // capturedBodies[2]: 3.8 Flash attempt 1
      expect(capturedBodies[2]['generationConfig']['thinkingConfig']['thinkingLevel'], 'LOW');

      // capturedBodies[3]: Hydrogen attempt 1
      expect(capturedBodies[3]['generationConfig']['thinkingConfig']['thinkingLevel'], 'LOW');
    });

    test('8. Models list does not contain deprecated models gemini-3.5-flash and gemini-2.5-flash', () {
      expect(GeminiService.models, contains('gemini-3.5-flash-lite'));
      expect(GeminiService.models, isNot(contains('gemini-3.5-flash')));
      expect(GeminiService.models, isNot(contains('gemini-2.5-flash')));
      expect(GeminiService.models, isNot(contains('gemini-2.5-flash-lite')));
      expect(GeminiService.models, isNot(contains('gemini-3.6-flash')));
      expect(GeminiService.models.length, 3);
    });
  });
}
