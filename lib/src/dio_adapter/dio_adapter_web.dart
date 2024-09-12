import 'package:dio/browser.dart';
import 'package:dio/dio.dart';
import 'package:sync_client/src/dio_adapter/dio_adapter.dart';

DioAdapterInterface getInstance() => DioAdapterWeb();

class DioAdapterWeb implements DioAdapterInterface {
  @override
  void initAdapter(Dio dio) {
    dio.httpClientAdapter = makeHttpClientAdapter();
  }
}

HttpClientAdapter makeHttpClientAdapter() {
  final adapter = HttpClientAdapter() as BrowserHttpClientAdapter;
  adapter.withCredentials = true;
  return adapter;
}
