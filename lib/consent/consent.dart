enum ConsentScope { doctorShare, ashaShare, cloudBackup, researchExport }

class ConsentRecord {
  const ConsentRecord({
    required this.visitId,
    required this.patientHash,
    required this.scopes,
    required this.recordedAt,
    required this.policyVersion,
    required this.screeningCompletedAt,
  });

  final String visitId;
  final String patientHash;
  final Set<ConsentScope> scopes;
  final DateTime recordedAt;
  final String policyVersion;
  final DateTime screeningCompletedAt;

  bool get doctorShare => scopes.contains(ConsentScope.doctorShare);
  bool get ashaShare => scopes.contains(ConsentScope.ashaShare);
  bool get cloudBackup => scopes.contains(ConsentScope.cloudBackup);
  bool get researchExport => scopes.contains(ConsentScope.researchExport);
  bool get hasAnyOnlineScope =>
      doctorShare || ashaShare || cloudBackup || researchExport;

  void validatePostResult() {
    if (recordedAt.isBefore(screeningCompletedAt)) {
      throw StateError(
        'Consent must be recorded after offline screening result.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'visitId': visitId,
    'patientHash': patientHash,
    'scopes': scopes.map((scope) => scope.name).toList()..sort(),
    'recordedAt': recordedAt.toIso8601String(),
    'policyVersion': policyVersion,
    'screeningCompletedAt': screeningCompletedAt.toIso8601String(),
  };

  factory ConsentRecord.fromJson(Map<String, Object?> json) => ConsentRecord(
    visitId: json['visitId'] as String,
    patientHash: json['patientHash'] as String,
    scopes: (json['scopes'] as List)
        .map((scope) => ConsentScope.values.byName(scope as String))
        .toSet(),
    recordedAt: DateTime.parse(json['recordedAt'] as String),
    policyVersion: json['policyVersion'] as String,
    screeningCompletedAt: DateTime.parse(
      json['screeningCompletedAt'] as String,
    ),
  );
}

class ConsentGate {
  const ConsentGate();

  void requireScope(ConsentRecord consent, ConsentScope scope) {
    consent.validatePostResult();
    if (!consent.scopes.contains(scope)) {
      throw StateError('Consent missing for ${scope.name}.');
    }
  }
}
