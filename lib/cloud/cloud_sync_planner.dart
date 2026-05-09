import '../consent/consent.dart';
import '../pipeline/screening_pipeline.dart';
import 'cloud_paths.dart';

class CloudUploadObject {
  const CloudUploadObject({
    required this.kind,
    required this.localPath,
    required this.storagePath,
    required this.contentType,
    required this.siteId,
  });

  final String kind;
  final String localPath;
  final String storagePath;
  final String contentType;
  final String siteId;
}

class CloudSyncPlan {
  const CloudSyncPlan({
    required this.caseId,
    required this.visitId,
    required this.uploads,
  });

  final String caseId;
  final String visitId;
  final List<CloudUploadObject> uploads;
}

class CloudSyncPlanner {
  const CloudSyncPlanner({CloudPaths paths = const CloudPaths()})
    : _paths = paths;

  final CloudPaths _paths;

  CloudSyncPlan doctorSharePlan({
    required String caseId,
    required ScreeningResult result,
    required ConsentRecord consent,
  }) {
    const ConsentGate().requireScope(consent, ConsentScope.doctorShare);
    _validateResultConsent(result, consent);
    final uploads = <CloudUploadObject>[];
    for (final artifact in result.segmentation) {
      final roiPath = _paths.roiImage(caseId, result.visitId, artifact.siteId);
      final maskPath = _paths.segmentationMask(
        caseId,
        result.visitId,
        artifact.siteId,
      );
      _paths.validateUploadPath(roiPath);
      _paths.validateUploadPath(maskPath);
      uploads.add(
        CloudUploadObject(
          kind: 'roiImage',
          localPath: artifact.roiImagePath,
          storagePath: roiPath,
          contentType: 'image/jpeg',
          siteId: artifact.siteId,
        ),
      );
      uploads.add(
        CloudUploadObject(
          kind: 'segmentationMask',
          localPath: artifact.maskPath,
          storagePath: maskPath,
          contentType: 'image/png',
          siteId: artifact.siteId,
        ),
      );
    }
    return CloudSyncPlan(
      caseId: caseId,
      visitId: result.visitId,
      uploads: uploads,
    );
  }

  void _validateResultConsent(ScreeningResult result, ConsentRecord consent) {
    if (consent.visitId != result.visitId ||
        consent.patientHash != result.patientHash) {
      throw StateError('Consent does not match screening result.');
    }
  }
}
