import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// The browser's fetch, with `credentials: 'include'` when [withCredentials].
http.Client dvBrowserHttpClient({required bool withCredentials}) =>
    BrowserClient()..withCredentials = withCredentials;
