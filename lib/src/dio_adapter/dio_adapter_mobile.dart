import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:sync_client/src/dio_adapter/dio_adapter.dart';

DioAdapterInterface getInstance() => DioAdapterMobile();

class DioAdapterMobile implements DioAdapterInterface {
  @override
  void initAdapter(Dio dio) {
    if (kIsWeb) {
      throw Exception("Wrong import, you should use the WEB version...");
    }
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        // Config the client.
        /*client.findProxy = (uri) {
          // Forward all request to proxy "localhost:8888".
          // Be aware, the proxy should went through you running device,
          // not the host platform.
          return 'PROXY localhost:9090';
        };*/
        // You can also create a new HttpClient for Dio instead of returning,
        // but a client must being returned here.
        return HttpClient();
      },
    );
  }
}
