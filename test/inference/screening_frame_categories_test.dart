import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/inference/screening_frame_categories.dart';

void main() {
  test('keeps novel category values from model JSON', () {
    final parsed = parseScreeningClassifierOutput('''
```json
{
  "category": "oral_cavity",
  "recommendation": "refer_for_clinical_review",
  "brief_reason": "clear oral cavity",
  "disclaimer": "not a diagnosis"
}
```''');
    expect(parsed['category'], 'oral_cavity');
    expect(parsed['recommendation'], 'refer_for_clinical_review');
  });

  test('majority category is most frequent label across frames', () {
    final maps = [
      {
        'category': 'oral_cavity',
        'recommendation': 'refer_for_clinical_review',
        'brief_reason': 'a',
        'disclaimer': '',
      },
      {
        'category': 'low_risk_or_variation',
        'recommendation': 'low_risk_or_variation',
        'brief_reason': 'b',
        'disclaimer': '',
      },
      {
        'category': 'low_risk_or_variation',
        'recommendation': 'low_risk_or_variation',
        'brief_reason': 'c',
        'disclaimer': '',
      },
      {
        'category': 'low_risk_or_variation',
        'recommendation': 'low_risk_or_variation',
        'brief_reason': 'd',
        'disclaimer': '',
      },
      {
        'category': 'oral_mucosa',
        'recommendation': 'refer_for_clinical_review',
        'brief_reason': 'e',
        'disclaimer': '',
      },
    ];
    final aggregation = ScreeningFrameAggregation.fromParsedMaps(maps);
    expect(aggregation.majorityCategory, 'low_risk_or_variation');
    expect(aggregation.categoryCounts['low_risk_or_variation'], 3);
    expect(aggregation.shouldRefer, isTrue);
  });
}
