import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

void main() async {
  final dio = Dio()
    ..interceptors.add(PrettyDioLogger(
      requestHeader: true,
      requestBody: true,
      responseBody: true,
      responseHeader: false,
      compact: false,
    ));

  try {
    await dio.get('http://www.mocky.io/v2/5d7fc75c3300000476f0b557');
  } catch (e) {
    print(e);
  }
}
