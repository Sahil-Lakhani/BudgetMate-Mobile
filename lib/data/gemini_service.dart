// Port of src/lib/gemini.js + api/_lib/geminiCore.js. With GEMINI_API_KEY set at build time
// (--dart-define-from-file=env.json) the app calls Gemini directly with the same model and
// prompts as the web server; otherwise it goes through the web app's /api/gemini endpoint.
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../core/config.dart';
import '../core/errors.dart';
import '../core/rate_limit.dart';
import 'models.dart';

const maxUploadBytes = 15 * 1024 * 1024;
const _maxEdge = 1600;

class GeminiService {
  GeminiService(this._auth, this._limiter, {http.Client? client, this.retryDelays = _defaultRetryDelays})
      : _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final RateLimiter _limiter;
  final http.Client _client;

  /// Waits between retries of a 503/429 from Gemini; its length is the number of retries.
  final List<Duration> retryDelays;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> payload) async {
    final user = _auth.currentUser;
    if (user == null) throw const UserFacingError('Your session has expired. Please sign in again.');
    if (geminiApiKey.isEmpty && apiBaseUrl.isEmpty) throw const UserFacingError('AI features are not configured in this build.');
    final conn = await Connectivity().checkConnectivity();
    if (conn.every((c) => c == ConnectivityResult.none)) {
      throw const UserFacingError('You appear to be offline. Check your connection and try again.');
    }
    if (geminiApiKey.isNotEmpty) return _callDirect(payload);

    final token = await user.getIdToken();
    // Play Integrity token: lets the server reject calls that don't come from the genuine app.
    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance.getToken();
    } catch (e) {
      debugPrint('[gemini] no App Check token: $e');
    }
    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$apiBaseUrl/api/gemini'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'X-Firebase-AppCheck': ?appCheckToken,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 70));
    } catch (_) {
      throw const UserFacingError("Couldn't reach the server. Check your connection and try again.");
    }

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw UserFacingError((data?['error'] as String?) ?? 'Something went wrong. Please try again.');
    }
    if (data == null) throw const UserFacingError('Something went wrong. Please try again.');
    return data;
  }

  /// Same request handling as handleGeminiRequest in geminiCore.js, minus the token check.
  Future<Map<String, dynamic>> _callDirect(Map<String, dynamic> payload) async {
    final List<Map<String, dynamic>> parts;
    if (payload['action'] == 'analyzeReceipt') {
      final image = payload['image'] as Map<String, String>;
      if (image['data']!.length > _maxImageBase64) throw const UserFacingError('Image is too large');
      parts = [
        {'text': _receiptPrompt},
        {
          'inline_data': {'mime_type': image['mimeType'], 'data': image['data']},
        },
      ];
    } else {
      final currency = RegExp(r'^[A-Z]{3}$').hasMatch('${payload['currency']}') ? payload['currency'] as String : 'EUR';
      parts = [
        {'text': _insightsPrompt(_minimiseTransactions(payload['transactions'] as List), currency)},
      ];
    }

    final body = jsonEncode({
      'contents': [
        {'parts': parts},
      ],
    });
    http.Response res;
    try {
      res = await sendWithRetry(
        () => _client
            .post(
              Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent'),
              headers: {'Content-Type': 'application/json', 'x-goog-api-key': geminiApiKey},
              body: body,
            )
            .timeout(const Duration(seconds: 70)),
        retryDelays,
      );
    } catch (_) {
      throw const UserFacingError("Couldn't reach the server. Check your connection and try again.");
    }

    if (res.statusCode == 429) throw const UserFacingError('Too many requests. Please wait a minute and try again.');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('[gemini] upstream error ${res.statusCode}: ${res.body}');
      throw const UserFacingError('The AI service is unavailable right now. Please try again later.');
    }

    String? text;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final candidates = body['candidates'] as List;
      final cParts = (candidates.first as Map)['content']['parts'] as List;
      text = cParts.map((p) => (p as Map)['text'] ?? '').join();
    } catch (_) {}
    if (text == null || text.isEmpty) throw const UserFacingError('The AI service returned no result. Please try again.');
    try {
      final json = text.replaceAll(RegExp(r'```(?:json)?\s*', caseSensitive: false), '').replaceAll('```', '').trim();
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      throw const UserFacingError('The AI service returned an unreadable result. Please try again.');
    }
  }

  /// Receipt OCR. Returns `{merchant, location, total, date, items:[…]}` like the web.
  Future<Map<String, dynamic>> analyzeReceipt(File file) async {
    _limiter.check('gemini-analyze');
    final image = await prepareImage(file);
    return _call({'action': 'analyzeReceipt', 'image': image});
  }

  /// AI saving tips for last month's transactions. Returns `{suggestions:[…]}`.
  Future<Map<String, dynamic>> generateMonthlyInsights(List<Txn> transactions, String currency) {
    _limiter.check('gemini-insights');
    return _call({
      'action': 'monthlyInsights',
      'transactions': transactions.map((t) => {'id': t.id, ...t.raw}).toList(),
      'currency': currency,
    });
  }
}

const _model = 'gemini-2.5-flash';
const _retryable = {429, 500, 503};
const _defaultRetryDelays = [Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8)];
const _maxImageBase64 = 4000000; // ~3 MB image; prepareImage downscales before upload
const _maxTransactions = 300;

// Prompts copied verbatim from api/_lib/geminiCore.js.
const _receiptPrompt = '''Analyze this receipt image and extract the following information in JSON format:
{
  "merchant": "store/business name",
  "location": "store/business location",
  "total": "total amount spent (as a number)",
  "date": "transaction date (YYYY-MM-DD format)",
  "items": [
    {
      "name": "item name (translate to English ONLY if it is a real, concrete noun like fruits, vegetables, food items, or branded products; if the name is a generic category or department label, keep it as a generic English description)",
      "unit_price": "item unit price (as a number)",
      "price": "item total price (as a number)",
      "quantity": "quantity (as a number, default 1)",
      "category": "one of: Groceries, Dining, Transport, Clothing, Household, Health, Entertainment, Subscription, Electronics, Other"
    }
  ]
}

Rules:
- Extract all items from the receipt
- Date must be in YYYY-MM-DD format; if no date is visible, use an empty string
- If category is unclear, use "Other"
- Translate item names to English ONLY if they are real, concrete nouns; do NOT invent specific product names for generic department labels
- Return ONLY valid JSON, no markdown, no code blocks, no explanations
- All prices must be numbers (no currency symbols)
- If the image is not a receipt, return {"merchant": "", "total": 0, "date": "", "items": []}''';

String _insightsPrompt(List<Map<String, dynamic>> transactions, String currency) => '''You are a personal finance assistant.

Analyze the following previous-month transaction data and generate exactly 3 to 4 specific, numerical and actionable money-saving suggestions.

Each suggestion MUST:
- Be strictly based on the provided data (no assumptions)
- Include real numbers from the data (prices, totals, differences, counts)
- Include a clear action the user can take
- Include a realistic estimated monthly saving

Focus on price comparisons of the same product across stores, repeatedly bought items, category overspending, bottle-deposit (Pfand) recovery where relevant, and drink/snack cutbacks.

DO NOT give generic advice, repeat the same type of suggestion, mention budgeting theory, or mention percentages without real amounts.
All amounts are in $currency.

Return JSON only:
{
  "suggestions": [
    {
      "title": "Short title (max 6 words)",
      "insight": "What happened, based on the data — short and to the point",
      "action": "What the user should do",
      "estimated_saving_per_month": 0
    }
  ]
}

Previous-month transaction data:
${jsonEncode(transactions)}''';

/// Gemini often answers 503 ("high demand"), 500 or 429 for a few seconds: wait and resend,
/// once per entry in [delays]. Returns the last response either way.
@visibleForTesting
Future<http.Response> sendWithRetry(Future<http.Response> Function() send, List<Duration> delays) async {
  var res = await send();
  for (final delay in delays) {
    if (!_retryable.contains(res.statusCode)) break;
    debugPrint('[gemini] ${res.statusCode}, retrying in ${delay.inSeconds}s');
    await Future<void>.delayed(delay);
    res = await send();
  }
  return res;
}

String _cut(Object? v, int max) {
  final s = '${v ?? ''}';
  return s.length > max ? s.substring(0, max) : s;
}

/// JS `Number(v) || def`.
num _num(Object? v, num def) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  return (n == null || n == 0 || n.isNaN) ? def : n;
}

/// Keep only what the prompt needs (data minimisation), as minimiseTransactions in geminiCore.js.
List<Map<String, dynamic>> _minimiseTransactions(List list) {
  if (list.isEmpty || list.length > _maxTransactions) throw const UserFacingError('Invalid transaction data');
  return list.map((t) {
    final m = t is Map ? t : const {};
    final items = m['lineItems'] is List ? (m['lineItems'] as List).take(100) : const [];
    return {
      'date': _cut(m['date'], 10),
      'merchant': _cut(m['merchant'], 100),
      'total': _num(m['total'], 0),
      'items': items.map((i) {
        final it = i is Map ? i : const {};
        return {
          'name': _cut(it['name'], 100),
          'price': _num(it['price'], 0),
          'quantity': _num(it['quantity'], 1),
          'category': _cut(it['category'], 40),
        };
      }).toList(),
    };
  }).toList();
}

/// Re-encode as JPEG, longest edge ≤ 1600px, EXIF (incl. GPS) dropped — same as the web.
Future<Map<String, String>> prepareImage(File file) async {
  final size = await file.length();
  if (size > maxUploadBytes) throw const UserFacingError('That image is larger than 15 MB. Please choose a smaller one.');
  final bytes = await file.readAsBytes();
  final jpeg = await compute(_downscaleJpeg, bytes);
  if (jpeg == null) throw const UserFacingError("This image format can't be processed here. Please use a JPG or PNG.");
  return {'data': base64Encode(jpeg), 'mimeType': 'image/jpeg'};
}

Uint8List? _downscaleJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > _maxEdge) {
    image = image.width >= image.height ? img.copyResize(image, width: _maxEdge) : img.copyResize(image, height: _maxEdge);
  }
  image.exif = img.ExifData();
  return img.encodeJpg(image, quality: 85);
}
