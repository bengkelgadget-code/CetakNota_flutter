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
        final rawText = '''```json
{
  "referensi": "REF999",
  "nama_penerima": "Siti",
  "bank_tujuan": "BRI",
  "rekening_tujuan": "987654",
  "nominal": 250000,
  "admin": 2500,
  "tanggal": "20/11/2026",
  "waktu": "09:00"
}
```''';
        final responsePayload = {
          "candidates": [
            {
              "content": {
                "parts": [
                  {"text": rawText}
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
      expect(result!['nama_penerima'], 'Siti');
      expect(result['nominal'], 250000);
      expect(result['admin'], 2500);
    });

    test('4. Lite 429 retries 1x after delay then succeeds; 429 twice moves to 3.8 Flash', () async {
      int liteAttempts = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('gemini-3.5-flash-lite')) {
          liteAttempts++;
          if (liteAttempts == 1) {
            return http.Response('{"error": "Too Many Requests"}', 429);
          }
          return http.Response(jsonEncode({
            "candidates": [
              {
                "content": {
                  "parts": [
                    {
                      "text": jsonEncode({
                        "nama_penerima": "Joko",
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
        }
        return http.Response('Not found', 404);
      });

      final result = await GeminiService.processReceipt(
        "dummy_base64",
        "Transfer",
        "test_api_key",
        client: mockClient,
        retryDelay: const Duration(milliseconds: 10),
      );

      expect(result, isNotNull);
      expect(liteAttempts, 2);
      expect(result!['nama_penerima'], 'Joko');

      int liteAttemptsB = 0;
      final requestedUrlsB = <String>[];
      final mockClientB = MockClient((request) async {
        requestedUrlsB.add(request.url.path);
        if (request.url.path.contains('gemini-3.5-flash-lite')) {
          liteAttemptsB++;
          return http.Response('{"error": "Too Many Requests"}', 429);
        } else if (request.url.path.contains('gemini-3.8-flash')) {
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
      expect(liteAttemptsB, 2);
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
        mainTimeout: const Duration(milliseconds: 20),
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

      expect(capturedBodies[0]['generationConfig']['responseMimeType'], 'application/json');
      expect(capturedBodies[0]['generationConfig']['maxOutputTokens'], 1024);
      expect(capturedBodies[0]['generationConfig']['thinkingConfig']['thinkingLevel'], 'MINIMAL');
      expect(capturedBodies[0]['generationConfig']['responseJsonSchema']['properties'], contains('token'));

      expect(capturedBodies[2]['generationConfig']['thinkingConfig']['thinkingLevel'], 'LOW');
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

    // B-F1 Tests
    test('9. B-F1: 3.8 Flash cadangan (maxAttempts=1) handles 400 thinking error and retries without thinkingConfig', () async {
      final capturedBodies = <Map<String, dynamic>>[];
      int flash38Calls = 0;

      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedBodies.add(body);

        if (request.url.path.contains('gemini-3.5-flash-lite')) {
          return http.Response('{"error": "rate limit"}', 429);
        } else if (request.url.path.contains('gemini-3.8-flash')) {
          flash38Calls++;
          if (flash38Calls == 1) {
            // First attempt to 3.8 Flash returns 400 with thinkingConfig error
            return http.Response(
              jsonEncode({
                "error": {
                  "code": 400,
                  "message": "Field 'thinkingConfig' is not supported for model gemini-3.8-flash",
                }
              }),
              400,
            );
          }
          // Second request to 3.8 Flash (without thinkingConfig) succeeds
          return http.Response(
            jsonEncode({
              "candidates": [
                {
                  "content": {
                    "parts": [
                      {
                        "text": jsonEncode({
                          "nama_penerima": "Budi Flash 3.8",
                          "bank_tujuan": "BRI",
                          "rekening_tujuan": "112233",
                          "nominal": 80000,
                          "admin": 0,
                          "tanggal": "20/11/2026",
                          "waktu": "15:00"
                        })
                      }
                    ]
                  }
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final result = await GeminiService.processReceipt(
        "dummy_base64",
        "Transfer",
        "test_api_key",
        client: mockClient,
        retryDelay: const Duration(milliseconds: 10),
      );

      expect(result, isNotNull);
      expect(result!['nama_penerima'], 'Budi Flash 3.8');
      expect(flash38Calls, 2);

      // Request 1 to 3.8 Flash had thinkingConfig
      expect(capturedBodies[2]['generationConfig']['thinkingConfig'], isNotNull);
      // Request 2 to 3.8 Flash did NOT have thinkingConfig
      expect(capturedBodies[3]['generationConfig']['thinkingConfig'], isNull);
    });

    test('10. B-F1: Lite (maxAttempts=2) handles 400 thinking then 429 retry and still succeeds', () async {
      int liteCalls = 0;
      final capturedBodies = <Map<String, dynamic>>[];

      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        capturedBodies.add(body);
        liteCalls++;

        if (liteCalls == 1) {
          // Attempt 0 with thinking returns 400 thinkingConfig
          return http.Response('{"error": "thinking_config not supported"}', 400);
        } else if (liteCalls == 2) {
          // Attempt 0 retry without thinking returns 429
          return http.Response('{"error": "Too Many Requests"}', 429);
        } else {
          // Attempt 1 retry succeeds
          return http.Response(
            jsonEncode({
              "candidates": [
                {
                  "content": {
                    "parts": [
                      {
                        "text": jsonEncode({
                          "nama_penerima": "Sari",
                          "bank_tujuan": "BCA",
                          "rekening_tujuan": "999",
                          "nominal": 25000,
                          "admin": 0,
                          "tanggal": "20/11/2026",
                          "waktu": "16:00"
                        })
                      }
                    ]
                  }
                }
              ]
            }),
            200,
          );
        }
      });

      final result = await GeminiService.processReceipt(
        "dummy_base64",
        "Transfer",
        "test_api_key",
        client: mockClient,
        retryDelay: const Duration(milliseconds: 10),
      );

      expect(result, isNotNull);
      expect(result!['nama_penerima'], 'Sari');
      expect(liteCalls, 3);
      expect(capturedBodies[0]['generationConfig']['thinkingConfig'], isNotNull);
      expect(capturedBodies[1]['generationConfig']['thinkingConfig'], isNull);
      expect(capturedBodies[2]['generationConfig']['thinkingConfig'], isNull);
    });

    // B-F2 Test
    test('11. B-F2: 400 schema error throws Exception mentioning Schema, NOT API Key', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            "error": {
              "code": 400,
              "message": "Invalid argument: responseJsonSchema properties invalid",
              "status": "INVALID_ARGUMENT",
            }
          }),
          400,
        );
      });

      expect(
        () => GeminiService.processReceipt(
          "dummy_base64",
          "Transfer",
          "test_api_key",
          client: mockClient,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf([
              contains('Schema'),
              isNot(contains('API Key Gemini ditolak')),
            ]),
          ),
        ),
      );
    });

    // B-F3 Test
    test('12. B-F3: 200 without candidates (e.g. SAFETY) logs reason and moves to next model', () async {
      final requestedUrls = <String>[];
      final mockClient = MockClient((request) async {
        requestedUrls.add(request.url.path);
        if (request.url.path.contains('gemini-3.5-flash-lite')) {
          return http.Response(
            jsonEncode({
              "candidates": [],
              "promptFeedback": {"blockReason": "SAFETY"}
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            "candidates": [
              {
                "content": {
                  "parts": [
                    {
                      "text": jsonEncode({
                        "nama_penerima": "Rina",
                        "bank_tujuan": "BSI",
                        "rekening_tujuan": "4455",
                        "nominal": 40000,
                        "admin": 0,
                        "tanggal": "20/11/2026",
                        "waktu": "17:00"
                      })
                    }
                  ]
                }
              }
            ]
          }),
          200,
        );
      });

      final result = await GeminiService.processReceipt(
        "dummy_base64",
        "Transfer",
        "test_api_key",
        client: mockClient,
      );

      expect(result, isNotNull);
      expect(result!['nama_penerima'], 'Rina');
      expect(requestedUrls.length, 2);
      expect(requestedUrls[0], contains('gemini-3.5-flash-lite'));
      expect(requestedUrls[1], contains('gemini-3.8-flash'));
    });
  });
}
