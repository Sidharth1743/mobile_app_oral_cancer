import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/models.dart';

String normalizeIdentityPart(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String patientHashForIdentity(IdentityRecord identity) {
  final normalized = [
    normalizeIdentityPart(identity.fullName),
    normalizeIdentityPart(identity.village),
    identity.dateOfBirth.toUtc().toIso8601String().split('T').first,
  ].join('|');
  return sha256.convert(utf8.encode(normalized)).toString();
}

String ageBandFromDateOfBirth(DateTime dob, {DateTime? now}) {
  final today = now ?? DateTime.now();
  var age = today.year - dob.year;
  final birthdayThisYear = DateTime(today.year, dob.month, dob.day);
  if (today.isBefore(birthdayThisYear)) {
    age -= 1;
  }
  if (age < 0) {
    throw ArgumentError.value(
      dob,
      'dob',
      'Date of birth cannot be in the future.',
    );
  }
  if (age < 18) {
    return '0-17';
  }
  if (age >= 85) {
    return '85+';
  }
  final lower = ((age - 18) ~/ 10) * 10 + 18;
  final upper = lower + 9;
  return '$lower-$upper';
}

String pinPrefix(String pinCode) {
  final digits = pinCode.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 3) {
    throw ArgumentError.value(
      pinCode,
      'pinCode',
      'PIN code must include at least 3 digits.',
    );
  }
  return digits.substring(0, 3);
}

String villageCode(String village) {
  final normalized = normalizeIdentityPart(village);
  if (normalized.isEmpty) {
    throw ArgumentError.value(village, 'village', 'Village is required.');
  }
  return sha256.convert(utf8.encode(normalized)).toString().substring(0, 12);
}

ClinicalRecord deIdentifyClinicalRecord({
  required String id,
  required IdentityRecord identity,
  required String gender,
  required String tobaccoBrand,
  required int chewsPerDay,
  required int yearsUsed,
  required bool alcoholUse,
  required DateTime createdAt,
  GeoCoords? coords,
}) {
  return ClinicalRecord(
    id: id,
    patientHash: patientHashForIdentity(identity),
    ageBand: ageBandFromDateOfBirth(identity.dateOfBirth, now: createdAt),
    pinPrefix: pinPrefix(identity.pinCode),
    villageCode: villageCode(identity.village),
    gender: gender,
    tobaccoBrand: tobaccoBrand,
    chewsPerDay: chewsPerDay,
    yearsUsed: yearsUsed,
    alcoholUse: alcoholUse,
    cei: calculateCei(
      tobaccoBrand: tobaccoBrand,
      chewsPerDay: chewsPerDay,
      yearsUsed: yearsUsed,
      alcoholUse: alcoholUse,
    ),
    createdAt: createdAt,
    coords: coords,
  );
}

const Map<String, double> tsnaBrandWeights = {
  'hans': 1.00,
  'pan parag': 0.95,
  'gutkha': 0.95,
  'khaini': 0.85,
  'zarda': 0.80,
  'mawa': 0.75,
  'betel quid with tobacco': 0.70,
  'paan with tobacco': 0.70,
  'smokeless tobacco': 0.65,
};

double calculateCei({
  required String tobaccoBrand,
  required int chewsPerDay,
  required int yearsUsed,
  required bool alcoholUse,
}) {
  if (chewsPerDay < 0 || yearsUsed < 0) {
    throw ArgumentError('Chews per day and years used must be non-negative.');
  }
  final normalizedBrand = normalizeIdentityPart(tobaccoBrand);
  final brandWeight = tsnaBrandWeights[normalizedBrand] ?? 0.50;
  final frequency = (chewsPerDay / 20).clamp(0.0, 1.0);
  final duration = (yearsUsed / 30).clamp(0.0, 1.0);
  final alcoholMultiplier = alcoholUse ? 1.15 : 1.0;
  final cei = brandWeight * frequency * duration * alcoholMultiplier;
  return cei.clamp(0.0, 1.0);
}
