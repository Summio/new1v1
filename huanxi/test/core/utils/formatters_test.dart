import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/utils/formatters.dart';

void main() {
  test('locationCity displays only city from province-city value', () {
    expect(Formatters.locationCity('广东省-深圳市'), '深圳市');
    expect(Formatters.locationCity('北京市-北京市'), '北京市');
  });

  test('locationCity keeps city-only values and blanks stable', () {
    expect(Formatters.locationCity('深圳市'), '深圳市');
    expect(Formatters.locationCity(''), '');
    expect(Formatters.locationCity(null), '');
  });
}
