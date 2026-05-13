import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class KeyValue {
  String key;
  String value;
  bool enabled;

  KeyValue({required this.key, required this.value, this.enabled = true});

  Map<String, dynamic> toJson() => {'key': key, 'value': value, 'enabled': enabled};
  factory KeyValue.fromJson(Map<String, dynamic> json) => KeyValue(
        key: json['key'] ?? '',
        value: json['value'] ?? '',
        enabled: json['enabled'] ?? true,
      );
}

class ApiRequest {
  String id;
  String name;
  String method;
  String url;
  List<KeyValue> params;
  List<KeyValue> headers;
  String body;
  DateTime timestamp;

  ApiRequest({
    required this.id,
    required this.name,
    required this.method,
    required this.url,
    required this.params,
    required this.headers,
    required this.body,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'method': method,
        'url': url,
        'params': params.map((e) => e.toJson()).toList(),
        'headers': headers.map((e) => e.toJson()).toList(),
        'body': body,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ApiRequest.fromJson(Map<String, dynamic> json) => ApiRequest(
        id: json['id'],
        name: json['name'],
        method: json['method'],
        url: json['url'],
        params: (json['params'] as List).map((e) => KeyValue.fromJson(e)).toList(),
        headers: (json['headers'] as List).map((e) => KeyValue.fromJson(e)).toList(),
        body: json['body'],
        timestamp: DateTime.parse(json['timestamp']),
      );
}

class Collection {
  String id;
  String name;
  List<ApiRequest> requests;

  Collection({required this.id, required this.name, required this.requests});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'requests': requests.map((e) => e.toJson()).toList(),
      };

  factory Collection.fromJson(Map<String, dynamic> json) => Collection(
        id: json['id'],
        name: json['name'],
        requests: (json['requests'] as List).map((e) => ApiRequest.fromJson(e)).toList(),
      );
}

class Environment {
  String name;
  List<KeyValue> variables;
  bool isActive;

  Environment({required this.name, required this.variables, this.isActive = false});

  Map<String, dynamic> toJson() => {
        'name': name,
        'variables': variables.map((e) => e.toJson()).toList(),
        'isActive': isActive,
      };

  factory Environment.fromJson(Map<String, dynamic> json) => Environment(
        name: json['name'],
        variables: (json['variables'] as List).map((e) => KeyValue.fromJson(e)).toList(),
        isActive: json['isActive'] ?? false,
      );
}

class ApiProvider extends ChangeNotifier {
  String _method = 'GET';
  String _url = '';
  List<KeyValue> _params = [KeyValue(key: '', value: '')];
  List<KeyValue> _headers = [KeyValue(key: '', value: '')];
  String _body = '';

  http.Response? _response;
  Duration? _responseTime;
  bool _isLoading = false;

  List<Collection> _collections = [];
  List<ApiRequest> _history = [];
  List<Environment> _environments = [Environment(name: 'Default', variables: [], isActive: true)];

  ApiProvider() {
    loadData();
  }

  // Getters
  String get method => _method;
  String get url => _url;
  List<KeyValue> get params => _params;
  List<KeyValue> get headers => _headers;
  String get body => _body;
  http.Response? get response => _response;
  Duration? get responseTime => _responseTime;
  bool get isLoading => _isLoading;
  List<Collection> get collections => _collections;
  List<ApiRequest> get history => _history;
  List<Environment> get environments => _environments;
  Environment get activeEnvironment => _environments.firstWhere((e) => e.isActive, orElse: () => _environments.first);

  // Setters
  void setMethod(String method) { _method = method; notifyListeners(); }
  void setUrl(String url) { _url = url; notifyListeners(); }
  void setBody(String body) { _body = body; notifyListeners(); }

  void addParam() { _params.add(KeyValue(key: '', value: '')); notifyListeners(); }
  void removeParam(int index) { _params.removeAt(index); if (_params.isEmpty) _params.add(KeyValue(key: '', value: '')); notifyListeners(); }

  void addHeader() { _headers.add(KeyValue(key: '', value: '')); notifyListeners(); }
  void removeHeader(int index) { _headers.removeAt(index); if (_headers.isEmpty) _headers.add(KeyValue(key: '', value: '')); notifyListeners(); }

  // Environment Interpolation
  String interpolate(String text) {
    String result = text;
    final env = activeEnvironment;
    for (var v in env.variables) {
      if (v.key.isNotEmpty) {
        result = result.replaceAll('{{${v.key}}}', v.value);
      }
    }
    return result;
  }

  Future<void> sendRequest() async {
    if (_url.isEmpty) return;
    _isLoading = true;
    _response = null;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    try {
      final interpolatedUrl = interpolate(_url);
      final uri = Uri.parse(interpolatedUrl).replace(
        queryParameters: {
          for (var p in _params)
            if (p.enabled && p.key.isNotEmpty) p.key: interpolate(p.value)
        },
      );

      final headerMap = {
        for (var h in _headers)
          if (h.enabled && h.key.isNotEmpty) h.key: interpolate(h.value)
      };

      http.Response res;
      final bodyToSubmit = interpolate(_body);

      switch (_method) {
        case 'POST': res = await http.post(uri, headers: headerMap, body: bodyToSubmit); break;
        case 'PUT': res = await http.put(uri, headers: headerMap, body: bodyToSubmit); break;
        case 'PATCH': res = await http.patch(uri, headers: headerMap, body: bodyToSubmit); break;
        case 'DELETE': res = await http.delete(uri, headers: headerMap, body: bodyToSubmit); break;
        default: res = await http.get(uri, headers: headerMap);
      }
      _response = res;

      // Add to history
      _history.insert(0, ApiRequest(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _url,
        method: _method,
        url: _url,
        params: List.from(_params),
        headers: List.from(_headers),
        body: _body,
        timestamp: DateTime.now(),
      ));
      if (_history.length > 50) _history.removeLast();
      saveData();
    } catch (e) {
      _response = http.Response('Error: $e', 500);
    } finally {
      stopwatch.stop();
      _responseTime = stopwatch.elapsed;
      _isLoading = false;
      notifyListeners();
    }
  }

  // Persistence
  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final collectionsJson = prefs.getString('collections');
    if (collectionsJson != null) {
      _collections = (json.decode(collectionsJson) as List).map((e) => Collection.fromJson(e)).toList();
    }
    final historyJson = prefs.getString('history');
    if (historyJson != null) {
      _history = (json.decode(historyJson) as List).map((e) => ApiRequest.fromJson(e)).toList();
    }
    final environmentsJson = prefs.getString('environments');
    if (environmentsJson != null) {
      _environments = (json.decode(environmentsJson) as List).map((e) => Environment.fromJson(e)).toList();
    }
    notifyListeners();
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('collections', json.encode(_collections.map((e) => e.toJson()).toList()));
    await prefs.setString('history', json.encode(_history.map((e) => e.toJson()).toList()));
    await prefs.setString('environments', json.encode(_environments.map((e) => e.toJson()).toList()));
  }

  void saveRequestToCollection(String collectionId, String name) {
    final request = ApiRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      method: _method,
      url: _url,
      params: List.from(_params),
      headers: List.from(_headers),
      body: _body,
      timestamp: DateTime.now(),
    );
    final collection = _collections.firstWhere((c) => c.id == collectionId);
    collection.requests.add(request);
    saveData();
    notifyListeners();
  }

  void createCollection(String name) {
    _collections.add(Collection(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, requests: []));
    saveData();
    notifyListeners();
  }

  void loadRequest(ApiRequest request) {
    _method = request.method;
    _url = request.url;
    _params = List.from(request.params);
    _headers = List.from(request.headers);
    _body = request.body;
    notifyListeners();
  }

  void addEnvironment(String name) {
    _environments.add(Environment(name: name, variables: []));
    saveData();
    notifyListeners();
  }

  void setActiveEnvironment(int index) {
    for (int i = 0; i < _environments.length; i++) {
      _environments[i].isActive = i == index;
    }
    saveData();
    notifyListeners();
  }

  void addEnvVar(int envIndex) {
    _environments[envIndex].variables.add(KeyValue(key: '', value: ''));
    notifyListeners();
  }

  double get payloadSizeKb => (_response?.bodyBytes.length ?? 0) / 1024;
}
