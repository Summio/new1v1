import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/data/china_location_data.dart';

void main() {
  test('china location data covers full province-city level list', () {
    expect(chinaProvinceCityMap.keys.length, 34);
    expect(chinaProvinceCityMap.containsKey('广东省'), isTrue);
    expect(chinaProvinceCityMap['广东省'], contains('梅州市'));
    expect(chinaProvinceCityMap['云南省'], contains('迪庆藏族自治州'));
    expect(chinaProvinceCityMap['黑龙江省'], contains('大兴安岭地区'));
    expect(chinaProvinceCityMap['新疆维吾尔自治区'], contains('吐鲁番市'));

    final levelTwoCount = chinaProvinceCityMap.values.fold<int>(
      0,
      (sum, cities) => sum + cities.length,
    );
    expect(levelTwoCount, greaterThan(300));
  });
}
