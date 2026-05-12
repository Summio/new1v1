import '../core/constants/api_endpoints.dart';
import '../core/network/dio_client.dart';

class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  final DioClient _dio = DioClient.instance;

  Future<Map<String, List<String>>> fetchChinaLocationMap() async {
    final data = await _dio.apiGet(ApiEndpoints.chinaLocations);
    final raw = data['data'];
    if (raw is! Map) {
      return const <String, List<String>>{};
    }

    final result = <String, List<String>>{};
    for (final entry in raw.entries) {
      final province = entry.key is String ? (entry.key as String).trim() : '';
      final value = entry.value;
      if (province.isEmpty || value is! List) {
        continue;
      }

      final cities = value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (cities.isNotEmpty) {
        result[province] = cities;
      }
    }
    return result;
  }
}
