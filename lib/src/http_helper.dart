import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sync_client/src/debug_utils.dart';
import 'package:sync_client/sync_client.dart';

const kMaxRetries = 5;
const kChunkSize = 10000;

final dio = Dio(
  BaseOptions(
      // connectTimeout: const Duration(seconds: 3),
      ),
);

class CustomHttpException implements Exception {
  final int statusCode;
  final String message;
  CustomHttpException({required this.statusCode, required this.message});

  @override
  String toString() {
    return message;
  }
}

class HttpHelper {
  /// Return a MAP from the downloaded JSON or throws an Exception
  ///
  Future<dynamic> call(String url, Map<String, String?>? params,
      {String? method,
      Object? body,
      Map<String, String> additionalHeaders = const {},
      isPushOrPull = false}) async {
    try {
      //DioAdapterInterface().initAdapter(dio);

      Map<String, String> headers = HashMap();
      headers['Accept'] = 'application/json';
      headers['Content-type'] = 'application/json; charset=utf-8';
      headers.addAll(additionalHeaders);
      // print(body);
      dynamic response;
      // Se sta facendo la GET per sapere se ci sono chunk sospesi non passar
      if (isPushOrPull && method == 'POST') {
        // Upload JSON Chuncked instead of pushing or pulling everything
        // final data = jsonEncode(body);
        //jsonDecode(body as String);
        response = await uploadJsonChunked(
            url: url,
            jsonString: body as String,
            chunkSize: kChunkSize,
            maxRetries: kMaxRetries,
            headers: headers);
      } else {
        switch (method) {
          case "POST":
            final data = jsonDecode(body as String);
            final options = Options(headers: headers);
            // This call make the first future to be exited, don't know why...
            response = await dio.post(url, data: data, options: options);
            break;
          default:
            response = await dio.get(url, options: Options(headers: headers));
        }
      }
      if (response.statusCode == 200) {
        // If the server did return a 200 OK response,
        // then parse the JSON.
        try {
          //print(response.data);
          // Se non va provare con Options(responseType: ResponseType.bytes)
          return response.data; //  utf8.decode(response.data.toString()));
        } catch (e) {
          // Non è stato possibile decodificare il json
          return null;
        }
      }
    } on DioException catch (e) {
      if (e is SocketException || e.response == null) {
        throw SyncException(e.toString(),
            type: SyncExceptionType.connectionException);
      }
      //debugPrint(e.toString());
      final response = e.response;
      if (response?.statusCode == 404) {
        //print("404 Not Found: $url");
        throw Exception("404 Not found - $url");
      } else if (response?.statusCode == 403) {
        throw UnauthorizedException();
      } else {
        // If the server did not return a 200 OK response,
        // then throw an exception.
        //throw Exception('Failed to load album');
        debugPrint(
            "${response?.statusCode} - Error downloading url: $url - ${response?.data}");
        String message;
        if (response!.data is Map) {
          message = response.data['message'];
        } else {
          message = response.data.toString();
        }
        throw CustomHttpException(
            statusCode: response.statusCode ?? 500, message: message);
      }
    } catch (e) {
      // It's not possible to get the real exception because of the
      // multiplatform nature of the http package
      if (e.toString().contains('Connection refused')) {
        throw SyncException(e.toString(),
            type: SyncExceptionType.connectionException);
      }
      //debugPrint(e.toString());
      rethrow;
    }
  }

  Future<Response> uploadJsonChunked(
      {required String url,
      required String jsonString,
      required int chunkSize,
      required int maxRetries,
      required Map<String, String> headers}) async {
    int totalSize = jsonString.length;
    int chunkIndex = 0;
    int retries = 0;
    dynamic finalResponse;
    // Let's KISS
    // Recupera l'ultimo chunk ricevuto dal server
    // try {
    //   Response resumeResponse =
    //       await dio.get(url, options: Options(headers: headers));
    //   if (resumeResponse.statusCode == 200) {
    //     chunkIndex = resumeResponse.data['lastChunk'];
    //     print("🔄 Riprendendo l'upload dal chunk: $chunkIndex");
    //   }
    // } catch (e) {
    //   print("⚠️ Non è stato possibile recuperare lo stato dell'upload: $e");
    // }

    while (chunkIndex * chunkSize < totalSize) {
      // Calcola il chunk da inviare
      int start = chunkIndex * chunkSize;
      int end = (start + chunkSize > totalSize) ? totalSize : start + chunkSize;
      String chunkData = jsonString.substring(start, end);
      int chunks = (totalSize / chunkSize).ceil();
      while (retries < maxRetries) {
        debugPrint("Sending $chunkIndex with ${chunkData.length} data");
        try {
          var response = await dio.post(
            url,
            data: jsonEncode({
              "chunkIndex": chunkIndex,
              "chunks": chunks,
              "data": chunkData,
              "start": start,
              "end": end
            }),
            options: Options(headers: headers),
          );

          if (response.statusCode == 200) {
            debugPrint("✅ Chunk $chunkIndex inviato con successo.");
            finalResponse = response; // Salva la response dell'ultimo chunk
            chunkIndex++;
            retries = 0;
            break;
          }
        } catch (e) {
          retries++;
          debugPrint(
              "⚠️ Tentativo $retries per il chunk $chunkIndex fallito: $e");
          await Future.delayed(
              Duration(seconds: 2 * retries)); // Backoff esponenziale
        }
      }

      if (retries >= maxRetries) {
        debugPrint("❌ Upload fallito dopo $maxRetries tentativi.");
        throw {"Upload fallito dopo $maxRetries tentativi"};
      }
    }

    debugPrint("✅ Upload JSON completato.");
    return finalResponse; // Ritorna la risposta del server dopo l'ultimo chunk
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

// class ExpiredTokenException implements Exception {}

class ConnectionRefusedException implements Exception {}

class UnauthorizedException implements Exception {}

// Expose a single instance of httpHelper
final HttpHelper httpHelper = HttpHelper();
