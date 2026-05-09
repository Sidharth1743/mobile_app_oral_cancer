class CloudPaths {
  const CloudPaths();

  String caseDocument(String caseId) => 'cases/$caseId';

  String patientIdentityDocument(String caseId) =>
      'cases/$caseId/private/patientIdentity';

  String consentDocument(String caseId, String consentId) =>
      'cases/$caseId/consents/$consentId';

  String screeningDocument(String caseId, String visitId) =>
      'cases/$caseId/screenings/$visitId';

  String doctorPackageDocument(String caseId, String packageId) =>
      'cases/$caseId/doctorPackages/$packageId';

  String storageObjectDocument(String caseId, String objectId) =>
      'cases/$caseId/storageObjects/$objectId';

  String roiImage(String caseId, String visitId, String siteId) =>
      'cases/$caseId/$visitId/roi/$siteId.jpg';

  String segmentationMask(String caseId, String visitId, String siteId) =>
      'cases/$caseId/$visitId/masks/$siteId.png';

  String selectedFrame(
    String caseId,
    String visitId,
    String siteId,
    int index,
  ) => 'cases/$caseId/$visitId/frames/${siteId}_$index.jpg';

  String researchExport(String exportId) => 'research/exports/$exportId.json';

  void validateUploadPath(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('/raw/') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.sqlite') ||
        lower.endsWith('.db') ||
        lower.endsWith('.litertlm')) {
      throw StateError('Unsupported cloud upload path: $path');
    }
  }
}
