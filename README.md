# pretty_dio_logger

a pretty logger for [Dio](https://pub.dev/packages/dio)

## Usage
Simply add PrettyDioLogger to your dio interceptors.
```Dart
Dio dio = Dio();
dio.interceptors.add(PrettyDioLogger());
// customization 
   dio.interceptors.add(PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
        error: true,
        compact: true,
        maxWidth: 60));
```

## How it looks like
![Response Example](https://github.com/Milad-Akarie/pretty_dio_logger/blob/master/images/log_example.png?raw=true "Response Example")
