import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

// ---------------------------------------------------------------------------
// Forked from pretty_dio_logger 1.4.0 with two extra features:
//   1. Base64 truncation  – values that look like base64 and exceed
//      [maxBase64Length] are shortened to the first [maxBase64Length] chars
//      followed by "…" so logs stay readable.
//   2. maxLines limit     – each section (request header, request body,
//      response header, response body) stops printing after [maxLines] lines.
//      Pass null to disable the limit (default behaviour).
// ---------------------------------------------------------------------------

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

  /// Log printer; defaults to console print.
  final void Function(Object object) logPrint;

  /// Filter request/response by [RequestOptions]
  final bool Function(RequestOptions options, FilterArgs args)? filter;

  /// Enable logPrint
  final bool enabled;

  // Internal line counter – reset before every section.
  int _lineCount = 0;
  bool _limitReached = false;

  /// Maximum number of lines to print for each log section
  /// (request header, request body, response header, response body).
  /// Set to null for unlimited output.
  final int? maxLines;

  /// Any string value longer than this that looks like base64 will be
  /// truncated. Defaults to 100 characters.
  final int maxBase64Length;

  /// Regex that matches a base64-encoded string (standard or URL-safe alphabet,
  /// with optional padding). We only flag it when it is longer than
  /// [maxBase64Length] so short values are never affected.
  static final _base64Re = RegExp(r'^[A-Za-z0-9+/\-_]+=*$');


  // Matches a data URI: data:<mime>;base64,<payload>
  static final _dataUriRe = RegExp(r'^(data:[^;]+;base64,)(.+)$', dotAll: true);

  // ignore: public_member_api_docs
  PrettyDioLogger({
    this.request = true,
    this.requestHeader = false,
    this.requestBody = false,
    this.responseHeader = false,
    this.responseBody = true,
    this.error = true,
    this.maxWidth = 90,
    this.compact = true,
    this.logPrint = print,
    this.filter,
    this.enabled = true,
    this.maxLines,
    this.maxBase64Length = 100,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final extra = Map.of(options.extra);
    options.extra[_timeStampKey] = DateTime.timestamp().millisecondsSinceEpoch;

    if (!enabled ||
        (filter != null &&
            !filter!(options, FilterArgs(false, options.data)))) {
      handler.next(options);
      return;
    }

    if (request) {
      _printRequestHeader(options);
    }

    if (requestHeader) {
      _resetCounter();
      _printMapAsTable(options.queryParameters, header: 'Query Parameters');
      final requestHeaders = <String, dynamic>{};
      requestHeaders.addAll(options.headers);
      if (options.contentType != null) {
        requestHeaders['contentType'] = options.contentType?.toString();
      }
      requestHeaders['responseType'] = options.responseType.toString();
      requestHeaders['followRedirects'] = options.followRedirects;
      if (options.connectTimeout != null) {
        requestHeaders['connectTimeout'] = options.connectTimeout?.toString();
      }
      if (options.receiveTimeout != null) {
        requestHeaders['receiveTimeout'] = options.receiveTimeout?.toString();
      }
      _printMapAsTable(requestHeaders, header: 'Headers');
      _printMapAsTable(extra, header: 'Extras');
    }

    if (requestBody && options.method != 'GET') {
      _resetCounter();
      final dynamic data = options.data;
      if (data != null) {
        if (data is Map) _printMapAsTable(options.data as Map?, header: 'Body');
        if (data is FormData) {
          final formDataMap = <String, dynamic>{}
            ..addEntries(data.fields)
            ..addEntries(data.files);
          _printMapAsTable(formDataMap, header: 'Form data | ${data.boundary}');
        } else {
          _printBlock(data.toString());
        }
      }
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!enabled ||
        (filter != null &&
            !filter!(
                err.requestOptions, FilterArgs(true, err.response?.data)))) {
      handler.next(err);
      return;
    }

    final triggerTime = err.requestOptions.extra[_timeStampKey];

    if (error) {
      if (err.type == DioExceptionType.badResponse) {
        final uri = err.response?.requestOptions.uri;
        int diff = 0;
        if (triggerTime is int) {
          diff = DateTime.timestamp().millisecondsSinceEpoch - triggerTime;
        }
        _printBoxed(
            header:
                'DioError ║ Status: ${err.response?.statusCode} ${err.response?.statusMessage} ║ Time: $diff ms',
            text: uri.toString());
        if (err.response != null && err.response?.data != null) {
          logPrint('╔ ${err.type.toString()}');
          _resetCounter();
          _printResponse(err.response!);
        }
        _printLine('╚');
        logPrint('');
      } else {
        _printBoxed(header: 'DioError ║ ${err.type}', text: err.message);
      }
    }
    handler.next(err);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!enabled ||
        (filter != null &&
            !filter!(
                response.requestOptions, FilterArgs(true, response.data)))) {
      handler.next(response);
      return;
    }

    final triggerTime = response.requestOptions.extra[_timeStampKey];

    int diff = 0;
    if (triggerTime is int) {
      diff = DateTime.timestamp().millisecondsSinceEpoch - triggerTime;
    }
    _printResponseHeader(response, diff);

    if (responseHeader) {
      _resetCounter();
      final responseHeaders = <String, String>{};
      response.headers
          .forEach((k, list) => responseHeaders[k] = list.toString());
      _printMapAsTable(responseHeaders, header: 'Headers');
    }

    if (responseBody) {
      _resetCounter();
      _safePrint('╔ Body');
      _safePrint('║');
      _printResponse(response);
      _safePrint('║');
      _printLine('╚');
    }

    handler.next(response);
  }

  void _resetCounter() {
    _lineCount = 0;
    _limitReached = false;
  }

  /// Prints [line] only when the maxLines limit has not been reached.
  /// When the limit is hit for the first time it prints a notice.
  void _safePrint(Object line) {
    if (maxLines == null) {
      logPrint(line);
      return;
    }
    if (_limitReached) return;
    if (_lineCount >= maxLines!) {
      _limitReached = true;
      logPrint('║');
      logPrint(
          '║ ======================= (output truncated at $maxLines lines) =======================');
      logPrint('║');
      return;
    }
    _lineCount++;
    logPrint(line);
  }

  /// Truncates long base64 content so logs stay readable.
  ///
  /// Handles two formats:
  ///  1. **Data URI** – `data:image/png;base64,<payload>`: keeps the prefix
  ///     and truncates only the payload part.
  ///  2. **Plain base64** – a raw base64 string without a prefix.
  ///
  /// Strings shorter than [maxBase64Length] are returned as-is.
  dynamic _truncateBase64(dynamic value) {
    if (value is! String) return value;

    // ── 1. data URI (e.g. "data:image/png;base64,iVBOR…") ──────────────────
    final uriMatch = _dataUriRe.firstMatch(value);
    if (uriMatch != null) {
      final prefix = uriMatch.group(1)!; // "data:image/png;base64,"
      final payload = uriMatch.group(2)!; // raw base64 characters
      if (payload.length > maxBase64Length) {
        return '$prefix${payload.substring(0, maxBase64Length)} …';
      }
      return value;
    }

    // ── 2. Plain base64 string ───────────────────────────────────────────────
    if (value.length > maxBase64Length &&
        _base64Re.hasMatch(value.replaceAll(RegExp(r'\s'), ''))) {
      return '${value.substring(0, maxBase64Length)} …';
    }

    return value;
  }

  // ---------------------------------------------------------------------------
  // Private print helpers (adapted to use _safePrint + truncation)
  // ---------------------------------------------------------------------------

  void _printBoxed({String? header, String? text}) {
    logPrint('');
    logPrint('╔╣ $header');
    logPrint('║  $text');
    _printLine('╚');
  }

  void _printResponse(Response response) {
    if (response.data != null) {
      if (response.data is Map) {
        _printPrettyMap(response.data as Map);
      } else if (response.data is Uint8List) {
        _safePrint('║${_indent()}[');
        _printUint8List(response.data as Uint8List);
        _safePrint('║${_indent()}]');
      } else if (response.data is List) {
        _safePrint('║${_indent()}[');
        _printList(response.data as List);
        _safePrint('║${_indent()}]');
      } else {
        _printBlock(response.data.toString());
      }
    }
  }

  void _printResponseHeader(Response response, int responseTime) {
    final uri = response.requestOptions.uri;
    final method = response.requestOptions.method;
    _printBoxed(
        header:
            'Response ║ $method ║ Status: ${response.statusCode} ${response.statusMessage}  ║ Time: $responseTime ms',
        text: uri.toString());
  }

  void _printRequestHeader(RequestOptions options) {
    final uri = options.uri;
    final method = options.method;
    _printBoxed(header: 'Request ║ $method ', text: uri.toString());
  }

  void _printLine([String pre = '', String suf = '╝']) =>
      logPrint('$pre${'═' * maxWidth}$suf');

  void _printKV(String? key, Object? v) {
    final truncated = _truncateBase64(v);
    final pre = '╟ $key: ';
    final msg = truncated.toString();

    if (pre.length + msg.length > maxWidth) {
      _safePrint(pre);
      _printBlock(msg);
    } else {
      _safePrint('$pre$msg');
    }
  }

  void _printBlock(String msg) {
    final lines = (msg.length / maxWidth).ceil();
    for (var i = 0; i < lines; ++i) {
      _safePrint((i >= 0 ? '║ ' : '') +
          msg.substring(i * maxWidth,
              math.min<int>(i * maxWidth + maxWidth, msg.length)));
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

    if (isRoot || isListItem) _safePrint('║$initialIndent{');

    for (var index = 0; index < data.length; index++) {
      final isLast = index == data.length - 1;
      final key = '"${data.keys.elementAt(index)}"';
      dynamic value = data[data.keys.elementAt(index)];

      if (value is String) {
        // First truncate base64, then quote
        final truncated = _truncateBase64(value);
        value =
            '"${truncated.toString().replaceAll(RegExp(r'([\r\n])+'), " ")}"';
      }

      if (value is Map) {
        if (compact && _canFlattenMap(value)) {
          _safePrint('║${_indent(tabs)} $key: $value${!isLast ? ',' : ''}');
        } else {
          _safePrint('║${_indent(tabs)} $key: {');
          _printPrettyMap(value, initialTab: tabs);
        }
      } else if (value is List) {
        if (compact && _canFlattenList(value)) {
          _safePrint('║${_indent(tabs)} $key: ${value.toString()}');
        } else {
          _safePrint('║${_indent(tabs)} $key: [');
          _printList(value, tabs: tabs);
          _safePrint('║${_indent(tabs)} ]${isLast ? '' : ','}');
        }
      } else {
        final msg = value.toString().replaceAll('\n', '');
        final indent = _indent(tabs);
        final linWidth = maxWidth - indent.length;
        if (msg.length + indent.length > linWidth) {
          final lines = (msg.length / linWidth).ceil();
          for (var i = 0; i < lines; ++i) {
            final multilineKey = i == 0 ? '$key:' : '';
            _safePrint(
                '║${_indent(tabs)} $multilineKey ${msg.substring(i * linWidth, math.min<int>(i * linWidth + linWidth, msg.length))}');
          }
        } else {
          _safePrint('║${_indent(tabs)} $key: $msg${!isLast ? ',' : ''}');
        }
      }
    }

    _safePrint('║$initialIndent}${isListItem && !isLast ? ',' : ''}');
  }

  void _printList(List list, {int tabs = kInitialTab}) {
    for (var i = 0; i < list.length; i++) {
      final element = list[i];
      final isLast = i == list.length - 1;
      if (element is Map) {
        if (compact && _canFlattenMap(element)) {
          _safePrint('║${_indent(tabs)}  $element${!isLast ? ',' : ''}');
        } else {
          _printPrettyMap(
            element,
            initialTab: tabs + 1,
            isListItem: true,
            isLast: isLast,
          );
        }
      } else {
        // Truncate base64 in list items too
        final truncated = _truncateBase64(element);
        _safePrint('║${_indent(tabs + 2)} $truncated${isLast ? '' : ','}');
      }
    }
  }

  void _printUint8List(Uint8List list, {int tabs = kInitialTab}) {
    var chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(
        list.sublist(
            i, i + chunkSize > list.length ? list.length : i + chunkSize),
      );
    }
    for (var element in chunks) {
      _safePrint('║${_indent(tabs)} ${element.join(", ")}');
    }
  }

  bool _canFlattenMap(Map map) {
    return map.values
            .where((dynamic val) => val is Map || val is List)
            .isEmpty &&
        map.toString().length < maxWidth;
  }

  bool _canFlattenList(List list) {
    return list.length < 10 && list.toString().length < maxWidth;
  }

  void _printMapAsTable(Map? map, {String? header}) {
    if (map == null || map.isEmpty) return;
    _safePrint('╔ $header ');
    for (final entry in map.entries) {
      _printKV(entry.key.toString(), entry.value);
    }
    _printLine('╚');
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
