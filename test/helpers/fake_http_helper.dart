import 'package:sync_client/sync_client.dart';

class FakeHttpHelper extends HttpHelper {
  final List<CallRecord> calls = [];
  final Map<RegExp, List<dynamic Function()>> _responseQueues = {};
  final Map<RegExp, Map<String, dynamic>> _staticResponses =
      _defaultResponses();

  static Map<RegExp, Map<String, dynamic>> _defaultResponses() {
    final now = DateTime.now();
    return {
      RegExp(r'/login/([^/]+)$'): {
        'accessToken': 'fake_access_token',
        'refreshToken': 'fake_refresh_token',
        'expires_on': now.add(const Duration(days: 1)).millisecondsSinceEpoch,
      },
      RegExp(r'/login/([^/]+)/refreshToken'): {
        'accessToken': 'refreshed_access_token',
        'refreshToken': 'new_refresh_token',
        'expires_on': now.add(const Duration(days: 1)).millisecondsSinceEpoch,
      },
      RegExp(r'/register/([^/]+)$'): {
        'user': {'name': 'Test User'},
      },
      RegExp(r'/pull/([^/]+)/([^/]+)$'): {
        'outdatedRowsGuid': <String>[],
        'data': <Map<String, dynamic>>[],
      },
      RegExp(r'/push/([^/]+)/([^/]+)$'): {
        'lastSync': DateTime.now().millisecondsSinceEpoch,
      },
      RegExp(r'/unregister/([^/]+)$'): {},
      RegExp(r'/password/([^/]+)/forgotten$'): {},
      RegExp(r'/password/([^/]+)/change$'): {},
      RegExp(r'/cancelSync/([^/]+)$'): {},
    };
  }

  void setResponse(RegExp urlPattern, Map<String, dynamic> response) {
    _staticResponses[urlPattern] = response;
  }

  void queueResponse(RegExp urlPattern, dynamic response) {
    _responseQueues.putIfAbsent(urlPattern, () => []);
    _responseQueues[urlPattern]!
        .add(() => response is Exception ? throw response : response);
  }

  void queueError(RegExp urlPattern, Exception error) {
    queueResponse(urlPattern, error);
  }

  @override
  Future<dynamic> call(String url, Map<String, String?>? params,
      {String? method,
      Object? body,
      Map<String, String> additionalHeaders = const {},
      isPushOrPull = false,
      SyncController? syncController}) async {
    calls.add(CallRecord(
      url: url,
      params: params,
      method: method,
      body: body,
      additionalHeaders: additionalHeaders,
    ));

    for (final entry in _responseQueues.entries) {
      if (entry.key.hasMatch(url) && entry.value.isNotEmpty) {
        final producer = entry.value.removeAt(0);
        return producer();
      }
    }

    for (final entry in _staticResponses.entries) {
      if (entry.key.hasMatch(url)) {
        return entry.value;
      }
    }

    return {};
  }

  void clearCalls() {
    calls.clear();
  }

  int get callCount => calls.length;

  List<String> get calledUrls => calls.map((c) => c.url).toList();

  void reset() {
    clearCalls();
    _responseQueues.clear();
    _staticResponses.clear();
    _staticResponses.addAll(_defaultResponses());
  }
}

class CallRecord {
  final String url;
  final Map<String, String?>? params;
  final String? method;
  final Object? body;
  final Map<String, String> additionalHeaders;

  CallRecord({
    required this.url,
    this.params,
    this.method,
    this.body,
    this.additionalHeaders = const {},
  });
}
