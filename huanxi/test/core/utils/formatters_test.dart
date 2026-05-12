import 'package:flutter_test/flutter_test.dart';
import 'package:huanxi/core/utils/formatters.dart';

void main() {
  test('locationCity displays only city from province-city value', () {
    expect(Formatters.locationCity('广东省-深圳市'), '深圳');
    expect(Formatters.locationCity('北京市-北京市'), '北京');
  });

  test('locationCity keeps city-only values and blanks stable', () {
    expect(Formatters.locationCity('深圳市'), '深圳');
    expect(Formatters.locationCity(''), '');
    expect(Formatters.locationCity(null), '');
  });

  test('locationCity trims common administrative suffixes for display', () {
    expect(Formatters.locationCity('北京市'), '北京');
    expect(Formatters.locationCity('内蒙古自治区-阿拉善盟'), '阿拉善');
    expect(Formatters.locationCity('黑龙江省-大兴安岭地区'), '大兴安岭');
    expect(Formatters.locationCity('临夏回族自治州'), '临夏回族');
  });
}
