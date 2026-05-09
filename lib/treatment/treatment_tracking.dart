enum TreatmentStatus {
  referred,
  appointmentBooked,
  doctorReviewed,
  treatmentStarted,
  completed,
}

class TreatmentEvent {
  const TreatmentEvent({
    required this.status,
    required this.recordedAt,
    required this.actorUid,
    required this.note,
  });

  final TreatmentStatus status;
  final DateTime recordedAt;
  final String actorUid;
  final String note;

  Map<String, Object?> toJson() => {
    'status': status.name,
    'recordedAt': recordedAt.toIso8601String(),
    'actorUid': actorUid,
    'note': note,
  };

  factory TreatmentEvent.fromJson(Map<String, Object?> json) => TreatmentEvent(
    status: TreatmentStatus.values.byName(json['status'] as String),
    recordedAt: DateTime.parse(json['recordedAt'] as String),
    actorUid: json['actorUid'] as String,
    note: json['note'] as String? ?? '',
  );
}

class TreatmentTimeline {
  const TreatmentTimeline({
    required this.visitId,
    required this.patientHash,
    required this.events,
  });

  final String visitId;
  final String patientHash;
  final List<TreatmentEvent> events;

  TreatmentStatus? get currentStatus =>
      events.isEmpty ? null : _sortedEvents.last.status;

  bool get completed => currentStatus == TreatmentStatus.completed;

  DateTime? get completedAt {
    final matches = _sortedEvents.where(
      (event) => event.status == TreatmentStatus.completed,
    );
    return matches.isEmpty ? null : matches.last.recordedAt;
  }

  TreatmentTimeline addEvent(TreatmentEvent event) {
    if (event.status == TreatmentStatus.completed &&
        currentStatus == TreatmentStatus.referred) {
      throw StateError('Treatment cannot be completed before review/start.');
    }
    return TreatmentTimeline(
      visitId: visitId,
      patientHash: patientHash,
      events: [...events, event]
        ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
    );
  }

  Map<String, Object?> toJson() => {
    'visitId': visitId,
    'patientHash': patientHash,
    'events': events.map((event) => event.toJson()).toList(),
  };

  factory TreatmentTimeline.fromJson(Map<String, Object?> json) =>
      TreatmentTimeline(
        visitId: json['visitId'] as String,
        patientHash: json['patientHash'] as String,
        events:
            (json['events'] as List? ?? const [])
                .map(
                  (event) => TreatmentEvent.fromJson(
                    Map<String, Object?>.from(event as Map),
                  ),
                )
                .toList()
              ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
      );

  List<TreatmentEvent> get _sortedEvents =>
      [...events]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
}
