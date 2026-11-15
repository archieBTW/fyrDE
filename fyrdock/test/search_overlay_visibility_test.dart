import 'package:flutter_test/flutter_test.dart';
import 'package:fyrdock/main.dart';

void main() {
  test('isSearchOverlayAppId matches search overlay identifiers only', () {
    expect(isSearchOverlayAppId('fyrsearch'), isTrue);
    expect(isSearchOverlayAppId('com.example.fyrsearch'), isTrue);
    expect(isSearchOverlayAppId('sway_launcher'), isTrue);
    expect(isSearchOverlayAppId('launcher'), isTrue);
    expect(isSearchOverlayAppId('fyroverview'), isFalse);
    expect(isSearchOverlayAppId('fyrterm'), isFalse);
    expect(isSearchOverlayAppId('firefox'), isFalse);
  });
}
