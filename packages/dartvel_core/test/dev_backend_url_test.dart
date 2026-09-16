// Which backend a development web build calls when the page was opened from a
// phone on the LAN rather than from the machine running `dartvel dev`.
import 'package:dartvel_core/dartvel.dart' show dvDevBackendUrl;
import 'package:test/test.dart';

void main() {
  test('a localhost backend is reached at the host the page came from', () {
    // The phone opened http://10.0.0.7:8080; its own localhost has no backend.
    expect(
      dvDevBackendUrl(
        'http://localhost:8081',
        page: Uri.parse('http://10.0.0.7:8080/orders'),
      ),
      'http://10.0.0.7:8081',
    );
    expect(
      dvDevBackendUrl(
        'http://127.0.0.1:8081/',
        page: Uri.parse('http://192.168.1.20:8080/'),
      ),
      'http://192.168.1.20:8081/',
    );
  });

  test('opened on the machine itself, nothing changes', () {
    expect(
      dvDevBackendUrl(
        'http://localhost:8081',
        page: Uri.parse('http://localhost:8080/'),
      ),
      'http://localhost:8081',
    );
  });

  test('a backend that is not on localhost is left alone', () {
    expect(
      dvDevBackendUrl(
        'https://api.example.com',
        page: Uri.parse('http://10.0.0.7:8080/'),
      ),
      'https://api.example.com',
    );
  });

  test('a page that was not served over http is left alone', () {
    expect(
      dvDevBackendUrl(
        'http://localhost:8081',
        page: Uri.parse('file:///index.html'),
      ),
      'http://localhost:8081',
    );
  });
}
