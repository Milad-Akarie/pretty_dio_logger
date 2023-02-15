# pretty_dio_logger

[![Pub](https://img.shields.io/pub/v/pretty_dio_logger.svg)](https://pub.dev/packages/pretty_dio_logger)

Pretty Dio logger is a [Dio](https://pub.dev/packages/dio) interceptor that logs network calls in a pretty, easy to read format.


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
        maxWidth: 90));
```

### Redaction from logs

If there is something that needs to be redacted from the logs extend the `PrettyDioLogger` class and add one of the following snippets:

#### Request
```dart
@override
RequestOptions redactRequest(RequestOptions redactedOptions) {
   // redaction logic

   return redactedOptions
}
```

#### Response
```dart
@override
Response redactResponse(Response redactedResponse) {
   // redaction logic

   return redactedResponse;
}
```

## How it looks like

### VS Code

![Request Example](https://github.com/Milad-Akarie/pretty_dio_logger/blob/master/images/request_log_vscode.png?raw=true 'Request Example')
![Error Example](https://github.com/Milad-Akarie/pretty_dio_logger/blob/master/images/error_log_vscode.png?raw=true 'Error Example')

### Android studio

![Response Example](https://github.com/Milad-Akarie/pretty_dio_logger/blob/master/images/response_log_android_studio.png?raw=true 'Response Example')
