import 'package:flutter_test/flutter_test.dart';
import 'package:sandfight/device_floor.dart';

void main() {
  test('iPhone 12 and later pass the floor, iPhone 11 does not', () {
    expect(meetsIphone12('iPhone12,1'), isFalse);
    expect(meetsIphone12('iPhone12,3'), isFalse);
    expect(meetsIphone12('iPhone12,8'), isFalse);
    expect(meetsIphone12('iPhone13,2'), isTrue);
    expect(meetsIphone12('iPhone13,1'), isTrue);
    expect(meetsIphone12('iPhone17,1'), isTrue);
    expect(meetsIphone12('arm64'), isTrue);
  });
}