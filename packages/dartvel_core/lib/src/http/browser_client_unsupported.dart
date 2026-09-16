import 'package:http/http.dart' as http;

/// Off the web there is no fetch credentials mode: a client sends the
/// headers it is given, and a cookie is one of them only when set.
http.Client dvBrowserHttpClient({required bool withCredentials}) => http.Client();
