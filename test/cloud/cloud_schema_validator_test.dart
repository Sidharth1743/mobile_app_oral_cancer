import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/cloud/cloud_schema_validator.dart';

void main() {
  test('rejects direct identity fields in public cloud payloads', () {
    const validator = CloudSchemaValidator();

    expect(
      () => validator.assertNoDirectIdentity({
        'caseId': 'case-1',
        'riskLevel': 'high',
        'nested': {'phone': '9999999999'},
      }),
      throwsStateError,
    );
    expect(
      () => validator.assertNoDirectIdentity({
        'caseId': 'case-1',
        'riskLevel': 'high',
        'villageCode': 'abc123',
      }),
      returnsNormally,
    );
  });

  test('validates consent payload scope and post-result time', () {
    const validator = CloudSchemaValidator();

    expect(
      () => validator.validateConsentPayload({
        'scopes': ['doctorShare'],
        'recordedAt': '2026-05-03T10:00:00.000Z',
        'screeningCompletedAt': '2026-05-03T09:00:00.000Z',
      }),
      returnsNormally,
    );
    expect(
      () => validator.validateConsentPayload({
        'scopes': ['doctorShare'],
        'recordedAt': '2026-05-03T08:00:00.000Z',
        'screeningCompletedAt': '2026-05-03T09:00:00.000Z',
      }),
      throwsStateError,
    );
    expect(
      () => validator.validateConsentPayload({
        'scopes': ['unknownScope'],
        'recordedAt': '2026-05-03T10:00:00.000Z',
        'screeningCompletedAt': '2026-05-03T09:00:00.000Z',
      }),
      throwsArgumentError,
    );
  });

  test('validates cloud storage object metadata', () {
    const validator = CloudSchemaValidator();

    expect(
      () => validator.validateStorageObjectMetadata({
        'kind': 'roiImage',
        'storagePath': 'cases/case-1/visit-1/roi/left.jpg',
        'contentType': 'image/jpeg',
      }),
      returnsNormally,
    );
    expect(
      () => validator.validateStorageObjectMetadata({
        'kind': 'segmentationMask',
        'storagePath': 'cases/case-1/visit-1/masks/left.png',
        'contentType': 'image/jpeg',
      }),
      throwsStateError,
    );
    expect(
      () => validator.validateStorageObjectMetadata({
        'kind': 'rawVideo',
        'storagePath': 'cases/case-1/visit-1/raw/video.mp4',
        'contentType': 'video/mp4',
      }),
      throwsStateError,
    );
  });

  test('validates user profile role document shape', () {
    const validator = CloudSchemaValidator();

    expect(
      () => validator.validateUserProfile({
        'uid': 'asha-1',
        'role': 'asha',
        'active': true,
      }),
      returnsNormally,
    );
    expect(
      () => validator.validateUserProfile({
        'uid': 'asha-1',
        'role': 'guest',
        'active': true,
      }),
      throwsArgumentError,
    );
    expect(
      () => validator.validateUserProfile({
        'uid': 'asha-1',
        'role': 'asha',
        'active': 'yes',
      }),
      throwsStateError,
    );
  });
}
