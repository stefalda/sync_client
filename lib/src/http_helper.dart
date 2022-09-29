import 'dart:collection';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CustomHttpException implements Exception {
  final int statusCode;
  final String message;
  CustomHttpException({required this.statusCode, required this.message});
}

class HttpHelper {
  /// Resituisce una MAP dal JSON scaricato o null in caso di errore
  static Future<dynamic> call(String url, Map<String, String?>? params,
      {String? method,
      Object? body,
      Map<String, String> additionalHeaders = const {}}) async {
    try {
      final bool isHTTPS = url.contains("https");
      if (isHTTPS) {
        url = url.substring(8);
      } else {
        url = url.substring(7);
      }
      int idx = url.indexOf("/");
      if (idx < 0) {
        idx = url.length;
      }

      //ATTENZIONE CHE VA IMPOSTATO A HTTPS IN PRODUZIONE
      var uri = isHTTPS
          ? Uri.https(url.substring(0, idx), url.substring(idx), params)
          : Uri.http(url.substring(0, idx), url.substring(idx), params);

      Map<String, String> headers = HashMap();
      headers['Accept'] = 'application/json';
      headers['Content-type'] = 'application/json; charset=utf-8';
      headers.addAll(additionalHeaders);
      print(body);
      dynamic response;
      switch (method) {
        case "POST":
          response = await http.post(uri, body: body, headers: headers);
          break;
        default:
          response = await http.get(uri, headers: headers);
      }
      if (response.statusCode == 200) {
        // If the server did return a 200 OK response,
        // then parse the JSON.
        try {
          print(response.body);
          return json.decode(utf8.decode(response.bodyBytes));
        } catch (e) {
          // Non è stato possibile decodificare il json
          return null;
        }
      } else if (response.statusCode == 404) {
        print("404 Not Found: $url");
        throw Exception("404 Not found");
      } else if (response.statusCode == 400) {
        throw ExpiredTokenException();
      } else {
        // If the server did not return a 200 OK response,
        // then throw an exception.
        //throw Exception('Failed to load album');
        print("Error downloading url: $url");
        throw CustomHttpException(
            statusCode: response.statusCode, message: response.body);
      }
      return null;
    }
    catch (e) {
      // It's not possible to get the real exception because of the
      // multiplatform nature of the http package
      if (e.toString().contains('Connection refused')) {
        throw ConnectionRefusedException();
      }
      print(e.toString());
      rethrow;
    }
  }

  /// Return the Simple Authentication header
  static Map<String, String> simpleAuthenticationHeader(
      {required String username, required String password}) {
    Codec<String, String> stringToBase64 = utf8.fuse(base64);
    String encoded = stringToBase64.encode("$username:$password");
    return {"Authorization": "Basic $encoded"};
  }

  /// Add the Bearer Authentication header
  static Map<String, String> bearerAuthenticationHeader(
      {required String token}) {
    return {"Authorization": "Bearer $token"};
  }
}

class ExpiredTokenException implements Exception {}

class ConnectionRefusedException implements Exception {}
