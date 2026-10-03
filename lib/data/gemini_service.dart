// Port of src/lib/gemini.js. Gemini is reached through the web app's own endpoint
// (api/gemini.js) with the user's Firebase ID token, so the API key stays on the server.
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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
  GeminiService(this._auth, this._limiter, {http.Client? client}) : _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final RateLimiter _limiter;
  final http.Client _client;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> payload) async {
    final user = _auth.currentUser;
    if (user == null) throw const UserFacingError('Your session has expired. Please sign in again.');
    if (apiBaseUrl.isEmpty) throw const UserFacingError('AI features are not configured in this build.');
    final conn = await Connectivity().checkConnectivity();
    if (conn.every((c) => c == ConnectivityResult.none)) {
      throw const UserFacingError('You appear to be offline. Check your connection and try again.');
    }

    final token = await user.getIdToken();
    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$apiBaseUrl/api/gemini'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
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
