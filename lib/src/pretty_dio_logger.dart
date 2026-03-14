import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

const _timeStampKey = '_pdl_timeStamp_';

/// A pretty logger for Dio
/// it will print request/response info with a pretty format
/// and also can filter the request/response by [RequestOptions]
class PrettyDioLogger extends Interceptor {
  /// Print request [Options]
  final bool request;

  /// Print request header [Options.headers]
  final bool requestHeader;

  /// Print request data [Options.data]
  final bool requestBody;

  /// Print [Response.data]
  final bool responseBody;

  /// Print [Response.headers]
  final bool responseHeader;

  /// Print error message
  final bool error;

  /// InitialTab count to logPrint json response
  static const int kInitialTab = 1;

  /// 1 tab length
  static const String tabStep = '    ';

  /// Print compact json response
  final bool compact;

  /// Width size per logPrint
  final int maxWidth;

  /// Size in which the Uint8List will be split
  static const int chunkSize = 20;

  /// Log printer; defaults logPrint log to console.
  /// In flutter, you'd better use debugPrint.
  /// you can also write log in a file.
  final void Function(Object object) logPrint;

  /// Filter request/response by [RequestOptions]
  final bool Function(RequestOptions options, FilterArgs args)? filter;

  /// Enable logPrint
  final bool enabled;

  /// Default constructor
  PrettyDioLogger({
    this.request = true,
    this.requestHeader = true,
    this.requestBody = true,
    this.responseHeader = true,
    this.responseBody = true,
    this.error = true,
    this.maxWidth = 90,
    this.compact = true,
    this.logPrint = print,
    this.filter,
    this.enabled = true,
  });

  bool _shouldSkip(RequestOptions options, FilterArgs args) {
    if (!enabled) return true;
    if (filter != null && !filter!(options, args)) return true;
    return false;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_timeStampKey] = DateTime.timestamp().millisecondsSinceEpoch;

    if (_shouldSkip(options, FilterArgs(false, options.data))) {
      handler.next(options);
      return;
    }

    if (request) {
      _printBoxed(
          header: 'Request ║ ${options.method} ', text: options.uri.toString());
    }

    if (requestHeader) {
      _printMapAsTable(options.queryParameters, header: 'Query Parameters');

      final reqHeaders = <String, dynamic>{
        ...options.headers,
        'responseType': options.responseType.toString(),
        'followRedirects': options.followRedirects,
        if (options.connectTimeout != null)
          'connectTimeout': options.connectTimeout?.toString(),
        if (options.receiveTimeout != null)
          'receiveTimeout': options.receiveTimeout?.toString(),
      };

      _printMapAsTable(reqHeaders, header: 'Request Headers');
      _printMapAsTable(options.extra, header: 'Extras');
    }

    if (requestBody && options.data != null) {
      final dynamic data = options.data;
      if (data is Map) {
        _printMapAsTable(data, header: 'Request Body');
      } else if (data is FormData) {
        final formDataMap = <String, dynamic>{
          ...Map.fromEntries(data.fields),
          ...Map.fromEntries(data.files),
        };
        _printMapAsTable(formDataMap, header: 'Form data | ${data.boundary}');
      } else {
        logPrint('╔ Unknown Form ');
        _printBlock(data.toString());
        _printLine('╚');
      }
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_shouldSkip(err.requestOptions, FilterArgs(true, err.response?.data))) {
      handler.next(err);
      return;
    }

    if (error) {
      if (err.type == DioExceptionType.badResponse) {
        final response = err.response;
        final uri = response?.requestOptions.uri;
        _printBoxed(
          header:
              'DioError ║ Status: ${response?.statusCode} ${response?.statusMessage} ║ Time: ${_calculateTimeDifference(err.requestOptions.extra)} ms',
          text: uri.toString(),
        );

        if (response?.data != null) {
          logPrint('╔ ${err.type.toString()}');
          _printResponse(response!);
        }

        _printLine('╚');

        if (responseHeader && response != null) {
          final responseHeaders =
              response.headers.map.map((k, v) => MapEntry(k, v.toString()));
          _printMapAsTable(responseHeaders, header: 'Response Headers');
        }
      } else {
        _printBoxed(header: 'DioError ║ ${err.type}', text: err.message);
      }
    }
    handler.next(err);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_shouldSkip(response.requestOptions, FilterArgs(true, response.data))) {
      handler.next(response);
      return;
    }

    _printBoxed(
      header:
          'Response ║ ${response.requestOptions.method} ║ Status: ${response.statusCode} ${response.statusMessage}  ║ Time: ${_calculateTimeDifference(response.requestOptions.extra)} ms',
      text: response.requestOptions.uri.toString(),
    );

    if (responseHeader) {
      final responseHeaders =
          response.headers.map.map((k, v) => MapEntry(k, v.toString()));
      _printMapAsTable(responseHeaders, header: 'Response Headers');
    }

    if (responseBody) {
      logPrint('╔ Body');
      logPrint('║');
      _printResponse(response);
      logPrint('║');
      _printLine('╚');
    }
    handler.next(response);
  }

  int _calculateTimeDifference(Map<String, dynamic> extra) {
    final triggerTime = extra[_timeStampKey];
    if (triggerTime is int) {
      return DateTime.timestamp().millisecondsSinceEpoch - triggerTime;
    }
    return 0;
  }

  void _printBoxed({String? header, String? text}) {
    logPrint('');
    logPrint('╔╣ $header');
    logPrint('║  $text');
    _printLine('╚');
  }

  void _printResponse(Response response) {
    final dynamic data = response.data;
    if (data == null) return;

    if (data is Map) {
      _printPrettyMap(data);
    } else if (data is Uint8List) {
      logPrint('║${_indent()}[');
      _printUint8List(data);
      logPrint('║${_indent()}]');
    } else if (data is List) {
      logPrint('║${_indent()}[');
      _printList(data);
      logPrint('║${_indent()}]');
    } else {
      _printBlock(data.toString());
    }
  }

  void _printLine([String pre = '', String suf = '╝']) =>
      logPrint('$pre${'═' * maxWidth}$suf');

  void _printKV(String? key, Object? v) {
    final pre = '╟ $key: ';
    final msg = v.toString();

    if (pre.length + msg.length > maxWidth) {
      logPrint(pre);
      _printBlock(msg);
    } else {
      logPrint('$pre$msg');
    }
  }

  void _printMapAsTable(Map? map, {String? header}) {
    if (map == null || map.isEmpty) return;

    // Removing the timestamp key so it doesn't pollute the logs
    final Map cleanMap = Map.from(map)..remove(_timeStampKey);
    if (cleanMap.isEmpty) return;

    logPrint('╔ $header ');
    for (final entry in cleanMap.entries) {
      _printKV(entry.key.toString(), entry.value);
    }
    _printLine('╚');
  }

  void _printBlock(String msg) {
    final lines = (msg.length / maxWidth).ceil();
    for (var i = 0; i < lines; ++i) {
      final start = i * maxWidth;
      final end = math.min(start + maxWidth, msg.length);
      logPrint('${i >= 0 ? '║ ' : ''}${msg.substring(start, end)}');
    }
  }

  String _indent([int tabCount = kInitialTab]) => tabStep * tabCount;

  void _printPrettyMap(
    Map data, {
    int initialTab = kInitialTab,
    bool isListItem = false,
    bool isLast = false,
  }) {
    var tabs = initialTab;
    final isRoot = tabs == kInitialTab;
    final initialIndent = _indent(tabs);
    tabs++;

    if (isRoot || isListItem) logPrint('║$initialIndent{');

    final keys = data.keys.toList();
    for (var index = 0; index < keys.length; index++) {
      final isLastItem = index == keys.length - 1;
      final rawKey = keys[index];
      final key = '"$rawKey"';
      dynamic value = data[rawKey];

      if (value is String) {
        value = '"${value.replaceAll(RegExp(r'[\r\n]+'), " ")}"';
      }

      final suffix = isLastItem ? '' : ',';

      if (value is Map) {
        if (compact && _canFlattenMap(value)) {
          logPrint('║${_indent(tabs)} $key: $value$suffix');
        } else {
          logPrint('║${_indent(tabs)} $key: {');
          _printPrettyMap(value, initialTab: tabs);
        }
      } else if (value is List) {
        if (compact && _canFlattenList(value)) {
          logPrint('║${_indent(tabs)} $key: $value$suffix');
        } else {
          logPrint('║${_indent(tabs)} $key: [');
          _printList(value, tabs: tabs);
          logPrint('║${_indent(tabs)} ]$suffix');
        }
      } else {
        _printValue(key, value.toString().replaceAll('\n', ''), tabs, suffix);
      }
    }

    logPrint('║$initialIndent}${isListItem && !isLast ? ',' : ''}');
  }

  void _printValue(String key, String msg, int tabs, String suffix) {
    final indent = _indent(tabs);
    final linWidth = maxWidth - indent.length;
    if (msg.length + indent.length > linWidth) {
      final lines = (msg.length / linWidth).ceil();
      for (var i = 0; i < lines; ++i) {
        final multilineKey = i == 0 ? "$key:" : "";
        final start = i * linWidth;
        final end = math.min(start + linWidth, msg.length);
        logPrint('║$indent $multilineKey ${msg.substring(start, end)}');
      }
    } else {
      logPrint('║$indent $key: $msg$suffix');
    }
  }

  void _printList(List list, {int tabs = kInitialTab}) {
    for (var i = 0; i < list.length; i++) {
      final element = list[i];
      final isLast = i == list.length - 1;
      final suffix = isLast ? '' : ',';

      if (element is Map) {
        if (compact && _canFlattenMap(element)) {
          logPrint('║${_indent(tabs)}  $element$suffix');
        } else {
          _printPrettyMap(
            element,
            initialTab: tabs + 1,
            isListItem: true,
            isLast: isLast,
          );
        }
      } else {
        logPrint('║${_indent(tabs + 2)} $element$suffix');
      }
    }
  }

  void _printUint8List(Uint8List list, {int tabs = kInitialTab}) {
    for (var i = 0; i < list.length; i += chunkSize) {
      final end = math.min(i + chunkSize, list.length);
      final chunk = list.sublist(i, end);
      logPrint('║${_indent(tabs)} ${chunk.join(", ")}');
    }
  }

  bool _canFlattenMap(Map map) {
    return !map.values.any((val) => val is Map || val is List) &&
        map.toString().length < maxWidth;
  }

  bool _canFlattenList(List list) {
    return list.length < 10 && list.toString().length < maxWidth;
  }
}

/// Filter arguments
class FilterArgs {
  /// If the filter is for a request or response
  final bool isResponse;

  /// if the [isResponse] is false, the data is the [RequestOptions.data]
  /// if the [isResponse] is true, the data is the [Response.data]
  final dynamic data;

  /// Returns true if the data is a string
  bool get hasStringData => data is String;

  /// Returns true if the data is a map
  bool get hasMapData => data is Map;

  /// Returns true if the data is a list
  bool get hasListData => data is List;

  /// Returns true if the data is a Uint8List
  bool get hasUint8ListData => data is Uint8List;

  /// Returns true if the data is a json data
  bool get hasJsonData => hasMapData || hasListData;

  /// Default constructor
  const FilterArgs(this.isResponse, this.data);
}
