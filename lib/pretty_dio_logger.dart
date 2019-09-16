library pretty_dio_logger;

import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

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

  /// initialTab count to print json response
  static const int initialTab = 2;

  /// 1 tab length
  static const String tabStep = '    ';

  /// print compact json response
  final bool compact;

  /// with size per print
  final int maxWidth;

  PrettyDioLogger(
      {this.request = true,
      this.requestHeader = true,
      this.requestBody = false,
      this.responseHeader = false,
      this.responseBody = true,
      this.error = true,
      this.maxWidth = 60,
      this.compact = false});

  @override
  FutureOr<dynamic> onRequest(RequestOptions options) {
    if (request) {
      _printRequestHeader(options);
    }
    if (requestHeader) {
      final headers = Map();
      if (options.headers != null) headers.addAll(options.headers);
      headers['contentType'] = options.contentType?.toString();
      headers['responseType'] = options.responseType?.toString();
      headers['followRedirects'] = options.followRedirects;
      headers['connectTimeout'] = options.connectTimeout;
      headers['receiveTimeout'] = options.receiveTimeout;
      _printMapAsTable(headers, header: 'Headers');

      if (options.extra != null) {
        _printMapAsTable(options.extra, header: 'Extras');
      }
    }
    if (requestBody && options.method != 'GET') {
      _printMapAsTable(options.data, header: 'Body');
    }
  }

  @override
  FutureOr<dynamic> onError(DioError err) {
    if (error) {
      final uri = err.response.request.uri;
      _printBoxed('DioError  ║  $uri ║ Status: ${err.response.statusCode} ${err.response.statusMessage}');
      if (err.response != null && err.response.data != null) {
        print('╔ ${err.type.toString()}');
        _printResponse(err.response);
      }
      _printLine('╚');
      print('');
    }
  }

  @override
  FutureOr<dynamic> onResponse(Response response) {
    _printResponseHeader(response);
    if (responseHeader) {
      final responseHeaders = Map<String, String>();
      response.headers.forEach((k, list) => responseHeaders[k] = list.toString());
      _printMapAsTable(responseHeaders, header: 'Headers');
    }

    if (responseBody) {
      print('╔ Body \n ║');
      _printResponse(response);
    }

    _printLine('║\n ╚');
  }

  void _printBoxed(String text) {
    _printLine('╔', '╗');
    print('║ $text');
    _printLine('╚', '╝');
  }

  void _printResponse(Response response) {
    if (response.data != null) {
      if (response.data is Map)
        _printPrettyMap(response.data);
      else if (response.data is List) {
        print('║${_getTabs()}[');
        _printList(response.data);
        print('║${_getTabs()}[');
      } else
        _printBlock(response.data);
    }
  }

  void _printResponseHeader(Response response) {
    final uri = response?.request?.uri;
    String method = response.request.method;
    _printBoxed(
        ' Response  ║  $method ${_getArrow(method)} $uri ║ Status: ${response.statusCode} ${response.statusMessage}');
  }

  String _getArrow(String method) {
    return (method == 'GET') ? ' <--' : '-->';
  }

  void _printRequestHeader(RequestOptions options) {
    final uri = options?.uri;
    String method = options?.method;
    _printBoxed(' Request  ║  $method ${_getArrow(method)} $uri ');
  }

  void _printLine([String pre = '', String suf = '╝']) => print('$pre${'═' * maxWidth}$suf');

  void _printKV(String key, Object v) {
    final pre = '╟ $key: ';
    final msg = v.toString();
    final maxLength = (maxWidth * 1.6).toInt();
    if (pre.length + msg.length > maxLength) {
      print(pre);
      _printBlock(msg);
    } else
      print('$pre$msg');
  }

  void _printBlock(String msg) {
    final maxLength = (maxWidth * 1.6).toInt();
    int lines = (msg.length / maxLength).ceil();
    for (int i = 0; i < lines; ++i) {
      print(
          (i >= 0 ? '║   ' : '') + msg.substring(i * maxLength, math.min<int>(i * maxLength + maxLength, msg.length)));
    }
  }

  String _getTabs([int tabCount = initialTab]) => tabStep * tabCount;

  void _printPrettyMap(Map data, {int tabs = initialTab, bool isListItem = false, bool isLast = false}) {
    final bool isRoot = tabs == initialTab;
    final initialIndent = _getTabs(tabs);
    tabs++;

    if (isRoot || isListItem) print('║$initialIndent{');

    data.keys.toList().asMap().forEach((index, key) {
      final isLast = index == data.length - 1;
      var value = data[key];
//      key = '\"$key\"';
      if (value is String) value = '\"$value\"';
      if (value is Map) {
        if (compact && _canFlattenMap(value))
          print('║${_getTabs(tabs)} $key: $value${!isLast ? ',' : ''}');
        else {
          print('║${_getTabs(tabs)} $key: {');
          _printPrettyMap(value, tabs: tabs);
        }
      } else if (value is List) {
        if (compact && _canFlattenList(value))
          print('║${_getTabs(tabs)} $key: ${value.toString()}');
        else {
          print('║${_getTabs(tabs)} $key: [');
          _printList(value, tabs: tabs);
          print('║${_getTabs(tabs)} ] ${isLast ? '' : ','}');
        }
      } else {
        print('║${_getTabs(tabs)} $key: ${_fixBreaks(value, tabs)}${!isLast ? ',' : ''}');
      }
    });

    print('║$initialIndent} ${isListItem && !isLast ? ',' : ''}');
  }

  void _printList(List list, {int tabs = initialTab}) {
    list.asMap().forEach((i, e) {
      final isLast = i == list.length - 1;
      if (e is Map) {
        if (compact && _canFlattenMap(e))
          print('║${_getTabs(tabs)}  $e ${!isLast ? ',' : ''}');
        else
          _printPrettyMap(e, tabs: tabs + 1, isListItem: true, isLast: isLast);
      } else
        print('║${_getTabs(tabs + 2)} $e ${isLast ? '' : ','}');
    });
  }

  bool _canFlattenMap(Map map) {
    return map.values.where((val) => val is Map || val is List).isEmpty && map.toString().length < maxWidth;
  }

  bool _canFlattenList(List list) {
    return (list.length < 10 && list.toString().length < maxWidth);
  }

  String _fixBreaks(value, int tabs) {
    return value.toString().replaceAll('\n', '\n ║ ${_getTabs(tabs)}');
  }

  void _printMapAsTable(Map map, {String header}) {
    if (map == null || map.isEmpty) return;
    print('╔ $header ');
    map.forEach((key, value) => _printKV(key, value));
    _printLine('╚');
  }
}
