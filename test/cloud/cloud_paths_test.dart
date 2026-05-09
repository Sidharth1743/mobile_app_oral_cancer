import 'package:flutter_test/flutter_test.dart';
import 'package:oral_cancer/cloud/cloud_paths.dart';

void main() {
  test('builds stable Firestore and Storage paths', () {
    const paths = CloudPaths();

    expect(paths.caseDocument('case-1'), 'cases/case-1');
    expect(
      paths.patientIdentityDocument('case-1'),
      'cases/case-1/private/patientIdentity',
    );
    expect(
      paths.screeningDocument('case-1', 'visit-1'),
      'cases/case-1/screenings/visit-1',
    );
    expect(
      paths.roiImage('case-1', 'visit-1', 'left_buccal'),
      'cases/case-1/visit-1/roi/left_buccal.jpg',
    );
    expect(
      paths.segmentationMask('case-1', 'visit-1', 'left_buccal'),
      'cases/case-1/visit-1/masks/left_buccal.png',
    );
  });

  test('rejects unsupported cloud upload paths', () {
    const paths = CloudPaths();

    expect(
      () => paths.validateUploadPath('cases/c/v/raw/video.mp4'),
      throwsStateError,
    );
    expect(
      () => paths.validateUploadPath('cases/c/v/model/file.litertlm'),
      throwsStateError,
    );
    expect(
      () => paths.validateUploadPath('cases/c/v/db/local.sqlite'),
      throwsStateError,
    );
    expect(
      () => paths.validateUploadPath('cases/c/v/roi/left.jpg'),
      returnsNormally,
    );
  });
}
