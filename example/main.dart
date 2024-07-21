import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/src/pretty_dio_logger.dart';

void main() async {
  final dio = Dio()
    ..interceptors.add(
      PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        filter: (options, args) {
          //  return !options.uri.path.contains('posts');
          return !args.isResponse || !args.hasUint8ListData;
        },
      ),
    );
  try {
    await dio.get('https://jsonplaceholder.typicode.com/posts/1');
  } catch (e) {
    print(e);
  }
}
