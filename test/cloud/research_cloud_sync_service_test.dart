import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/cloud/research_cloud_sync_service.dart';

void main() {
  test('research cloud uploader rejects direct identity keys recursively', () {
    expect(
      () => ResearchCloudFunctionUploader.validateResearchPayload({
        'visitId': 'visit-1',
        'consent': const {
          'scopes': ['researchExport'],
        },
        'export': const {'phone': '9999999999'},
      }),
      throwsStateError,
    );
  });
}
