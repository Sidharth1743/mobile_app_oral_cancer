import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/location/indian_locations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Tamil Nadu location asset loads 38 districts', () async {
    final catalog = await IndiaLocationCatalog.load(bundle: rootBundle);
    final districts = catalog.districtsForState('Tamil Nadu');

    expect(districts, hasLength(38));
    expect(districts.first, 'Ariyalur');
    expect(districts, contains('Chennai'));
    expect(districts, contains('Virudhunagar'));
  });

  test('district list changes by selected state', () async {
    final catalog = await IndiaLocationCatalog.load(bundle: rootBundle);

    expect(catalog.districtsForState('TN'), hasLength(38));
    expect(catalog.districtsForState('Kerala'), isEmpty);
  });
}
