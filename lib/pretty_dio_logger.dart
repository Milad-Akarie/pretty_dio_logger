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

  /// Log size per print
  final logSize;

  /// initialTab count to print json response
  static const int initialTab = 2;

  /// 1 tab length
  static const String tabStep = '    ';

  /// print compact json response
  final bool compact;

  /// the length of the divider line
  final int dividerLength;

  PrettyDioLogger(
      {this.request = true,
      this.requestHeader = true,
      this.requestBody = false,
      this.responseHeader = true,
      this.responseBody = false,
      this.error = true,
      this.logSize = 2048,
      this.dividerLength = 60,
      this.compact = true});

  @override
  FutureOr<dynamic> onRequest(RequestOptions options) {
    if (request) {
      _printRequestHeader(options);
    }
    if (requestHeader) {
      _printMapAsTable(options.data, header: '═╡Headers  ----------------------------------');
      if (options.extra != null) {
        _printMapAsTable(options.extra, header: '═╡Extras  ----------------------------------');
      }
    }
    if (requestBody && options.method != 'GET') {
      _printMapAsTable(options.data, header: '═╡Body     -----------------------------------');
    }
  }

  @override
  FutureOr<dynamic> onError(DioError err) {
    if (error) {
      final uri = err.response.request.uri;
      print('\n ═╡DioError  $uri ╞╡ Status: ${err.response.statusCode} ${err.response.statusMessage}');
      if (err.response != null && err.response.data != null) {
        print('═╡${err.type.toString()}');
        _printResponse(err.response);
      }
      _printLine();
    }
  }

  @override
  FutureOr<dynamic> onResponse(Response response) {
    _printResponseHeader(response);
    if (responseHeader) {
      final responseHeaders = Map<String, String>();
      response.headers.forEach((k, list) => responseHeaders[k] = list.toString());
      _printMapAsTable(responseHeaders, header: '═╡Headers  ----------------------------------');
    }

    if (responseBody) {
      print('═╡body    ----------------------------------');
      _printResponse(response);
    }

    _printLine();
  }

  void _printResponse(Response response) {
    if (response.data != null) {
      if (response.data is Map)
        _printPrettyMap(response.data);
      else if (response.data is List) {
        print('${_getTabs()}[');
        _printList(response.data);
        print('${_getTabs()}[');
      } else
        // print(response.data);
        _printBlock(response.data);
    }
  }

  void _printResponseHeader(Response response) {
    final uri = response?.request?.uri;
    String method = response.request.method;
    print(
        '\n ═╡Response  [ $method ]${_getArrow(method)} $uri ╞╡ Status: ${response.statusCode} ${response.statusMessage}');
  }

  String _getArrow(String method) {
    return (method == 'GET') ? ' <--' : '-->';
  }

  void _printRequestHeader(RequestOptions options) {
    final uri = options?.uri;
    String method = options?.method;
    print('\n ═╡Request   [ $method ]${_getArrow(method)} $uri ╞═══════');
    if (requestHeader) {
      _printKV('contentType', options.contentType?.toString());
      _printKV('responseType', options.responseType?.toString());
      _printKV('followRedirects', options.followRedirects);
      _printKV('connectTimeout', options.connectTimeout);
      _printKV('receiveTimeout', options.receiveTimeout);
    }
  }

  void _printLine() => print('═' * dividerLength);

  void _printKV(String key, Object v) => print('   ╞ $key: $v');

  void _printBlock(String msg) {
    int groups = (msg.length / logSize).ceil();
    for (int i = 0; i < groups; ++i) {
      print((i >= 0 ? '   ╞ ' : '') + msg.substring(i * logSize, math.min<int>(i * logSize + logSize, msg.length)));
    }
  }

  String _getTabs([int tabCount = initialTab]) => tabStep * tabCount;

  void _printPrettyMap(Map data, {int tabs = initialTab, bool isListItem = false, bool isLast = false}) {
    final bool isRoot = tabs == initialTab;
    final initialIndent = _getTabs(tabs);
    tabs++;

    if (isRoot || isListItem) print('$initialIndent{');

    data.keys.toList().asMap().forEach((index, key) {
      final isLast = index == data.length - 1;
      final value = data[key];
      if (value is Map) {
        if (compact && _canFlattenMap(value))
          print('${_getTabs(tabs)} $key: $value${!isLast ? ',' : ''}');
        else {
          print('${_getTabs(tabs)} $key: {');
          _printPrettyMap(value, tabs: tabs);
        }
      } else if (value is List) {
        if (compact && _canFlattenList(value))
          print('${_getTabs(tabs)} $key: ${value.toString()}');
        else {
          print('${_getTabs(tabs)} $key: [');
          _printList(value, tabs: tabs);
          print('${_getTabs(tabs)} ] ${isLast ? '' : ','}');
        }
      } else {
        print('${_getTabs(tabs)} $key: ${_fixBreaks(value, tabs)}${!isLast ? ',' : ''}');
      }
    });

    print('$initialIndent} ${isListItem && !isLast ? ',' : ''}');
  }

  void _printList(List list, {int tabs = initialTab}) {
    list.asMap().forEach((i, e) {
      final isLast = i == list.length - 1;
      if (e is Map) {
        if (compact && _canFlattenMap(e))
          print('${_getTabs(tabs)}  $e ${!isLast ? ',' : ''}');
        else
          _printPrettyMap(e, tabs: tabs + 1, isListItem: true, isLast: isLast);
      } else
        print('${_getTabs(tabs + 2)} $e ${isLast ? '' : ','}');
    });
  }

  bool _canFlattenMap(Map map) {
    return map.values.where((val) => val is Map || val is List).isEmpty && map.toString().length < 100;
  }

  bool _canFlattenList(List list) {
    return (list.length < 10 && list.toString().length < 100);
  }

  String _fixBreaks(value, int tabs) {
    return value.toString().replaceAll('\n|\r', '\n ${_getTabs(tabs)}');
  }

  void _printMapAsTable(Map map, {String header}) {
    if (map == null || map.isEmpty) return;
    print(header);
    map.forEach((key, value) => _printKV(key, value));
  }
}
