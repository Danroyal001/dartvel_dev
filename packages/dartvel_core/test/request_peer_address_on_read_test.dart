// A server knows the connection's address as text and most handlers never
// ask for it, so Request.peerAddressOf parses it the first time
// peerAddress is read, once. A request given an address outright keeps it.
import 'package:dartvel_core/http.dart';
import 'package:test/test.dart';

Request _request({DVPeerAddress? peer, DVPeerAddress? Function()? of}) => Request(
      method: 'GET',
      url: Uri.parse('http://localhost/'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
      peerAddress: peer,
      peerAddressOf: of,
    );

void main() {
  test('the address is read when first asked for, once', () {
    var parsed = 0;
    final Request request = _request(of: () {
      parsed++;
      return DVPeerAddress.tryParse('10.1.2.3:4567');
    });
    expect(parsed, 0);
    expect(request.peerAddress?.toString(), DVPeerAddress.tryParse('10.1.2.3:4567').toString());
    expect(request.peerAddress, isNotNull);
    expect(parsed, 1);
  });

  test('an address given outright is kept, and none is null', () {
    final DVPeerAddress given = DVPeerAddress.tryParse('[::1]:80')!;
    expect(_request(peer: given).peerAddress, same(given));
    expect(_request().peerAddress, isNull);
    expect(_request(of: () => null).peerAddress, isNull);
  });
}
