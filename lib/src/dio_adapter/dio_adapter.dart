import 'package:dio/dio.dart';
import 'package:sync_client/src/dio_adapter/dio_adapter_helper.dart'
    if (dart.library.io) './dio_adapter_mobile.dart'
    if (dart.library.html) './dio_adapter_web.dart';

import 'dio_adapter_mobile.dart'
    if (dart.library.js_interop) 'dio_adapter_web.dart' as adapter;

abstract class DioAdapterInterface {
  factory DioAdapterInterface() => getInstance();
  void initAdapter(Dio dio);
}

HttpClientAdapter makeHttpClientAdapter() => adapter.makeHttpClientAdapter();
