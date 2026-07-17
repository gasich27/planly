import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../config/api_config.dart';
import '../../utils/file_utils.dart';
import '../models/dashboard_model.dart';
import '../models/plan_model.dart';

// 🔌 LOGIC-LOCKED: Не меняй без необходимости
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  final http.Client _client;
  final Uuid _uuid = const Uuid();

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path) {
    final base = ApiConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$cleanPath');
  }

  Future<Map<String, dynamic>> _decodeJsonResponse(http.Response response) async {
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Request failed';
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          message = decoded['detail']?.toString() ??
              decoded['error']?.toString() ??
              message;
        }
      } catch (_) {
        if (body.trim().isNotEmpty) {
          message = body;
        }
      }
      throw ApiException(message, statusCode: response.statusCode);
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const ApiException('Invalid JSON response');
  }

  Future<String> transcribeAudio(File audio) async {
    try {
      final request = http.MultipartRequest('POST', _uri('/api/transcribe'));
      request.files.add(await http.MultipartFile.fromPath('audio', audio.path));
      final streamed = await request.send().timeout(ApiConfig.timeout);
      final response = await http.Response.fromStream(streamed);
      final data = await _decodeJsonResponse(response);
      return data['text']?.toString() ?? '';
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Transcription failed: $e');
    }
  }

  Future<PlanModel> generatePlan(String text, String period) async {
    try {
      final response = await _client
          .post(
            _uri('/api/plan'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'text': text,
              'period': period,
            }),
          )
          .timeout(ApiConfig.timeout);
      final data = await _decodeJsonResponse(response);
      return PlanModel.fromJson(data);
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Plan generation failed: $e');
    }
  }

  Future<List<PlanModel>> getPlans() async {
    try {
      final response = await _client
          .get(
            _uri('/api/plans'),
            headers: <String, String>{
              'Accept': 'application/json',
            },
          )
          .timeout(ApiConfig.timeout);
      final data = await _decodeJsonResponse(response);
      final items = data['items'];
      if (items is! List) {
        return <PlanModel>[];
      }
      return items.whereType<Map<String, dynamic>>().map(PlanModel.fromJson).toList();
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to load plans: $e');
    }
  }

  Future<PlanModel> getLatestPlan() async {
    try {
      final response = await _client
          .get(
            _uri('/api/latest-plan'),
            headers: <String, String>{
              'Accept': 'application/json',
            },
          )
          .timeout(ApiConfig.timeout);
      final data = await _decodeJsonResponse(response);
      return PlanModel.fromJson(data);
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to load latest plan: $e');
    }
  }

  Future<DashboardModel> getDashboard(String context, {DateTime? date}) async {
    try {
      final query = <String, String>{'context': context};
      if (date != null) {
        query['date_value'] = date.toIso8601String().substring(0, 10);
      }
      final response = await _client
          .get(
            _uri('/api/dashboard').replace(queryParameters: query),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(ApiConfig.timeout);
      return DashboardModel.fromJson(await _decodeJsonResponse(response));
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Request timed out');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to load dashboard: $e');
    }
  }

  Future<void> updateTaskStatus(int planId, int taskId, String status) async {
    try {
      final response = await _client
          .patch(
            _uri('/api/tasks/$planId/$taskId/status'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'status': status,
            }),
          )
          .timeout(ApiConfig.timeout);
      await _decodeJsonResponse(response);
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to update task status: $e');
    }
  }

  Future<PlanModel> aiEditPlan(int planId, String instruction) async {
    try {
      final response = await _client
          .post(
            _uri('/api/plans/$planId/ai-edit'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{'instruction': instruction}),
          )
          .timeout(ApiConfig.timeout);
      return PlanModel.fromJson(await _decodeJsonResponse(response));
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on TimeoutException {
      throw const ApiException('Request timed out');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('AI edit failed: $e');
    }
  }

  Future<File> exportIcs(int planId) async {
    try {
      final response = await _client
          .get(
            _uri('/api/export/$planId/ics'),
            headers: <String, String>{
              'Accept': 'text/calendar',
            },
          )
          .timeout(ApiConfig.timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = utf8.decode(response.bodyBytes);
        throw ApiException(body.isEmpty ? 'Export failed' : body, statusCode: response.statusCode);
      }

      final tempFileName = 'plan_${planId}_${_uuid.v4()}.ics';
      return await saveBytesToTempFile(response.bodyBytes, fileName: tempFileName);
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on TimeoutException catch (_) {
      throw const ApiException('Request timed out');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to export ICS: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
