import 'dart:convert';

import '../inference/gemma_service.dart';
import '../inference/strict_json.dart';

class ExtractedIntake {
  const ExtractedIntake({
    this.patientName,
    this.villageOrArea,
    this.state,
    this.district,
    this.age,
    this.gender,
    this.tobaccoUse,
    this.tobaccoBrand,
    this.chewsPerDay,
    this.yearsUsed,
    this.alcoholUse,
    this.symptoms = const [],
    this.symptomDuration,
    this.missingFields = const [],
    this.confidence = 0,
    required this.modelName,
    required this.rawJson,
  });

  final String? patientName;
  final String? villageOrArea;
  final String? state;
  final String? district;
  final int? age;
  final String? gender;
  final bool? tobaccoUse;
  final String? tobaccoBrand;
  final int? chewsPerDay;
  final int? yearsUsed;
  final bool? alcoholUse;
  final List<String> symptoms;
  final String? symptomDuration;
  final List<String> missingFields;
  final double confidence;
  final String modelName;
  final Map<String, Object?> rawJson;

  bool get hasAnyPrefill =>
      patientName != null ||
      villageOrArea != null ||
      state != null ||
      district != null ||
      age != null ||
      gender != null ||
      tobaccoUse != null ||
      tobaccoBrand != null ||
      chewsPerDay != null ||
      yearsUsed != null ||
      alcoholUse != null ||
      symptoms.isNotEmpty ||
      symptomDuration != null;
}

class IntakeExtractionService {
  const IntakeExtractionService({required GemmaService gemmaService})
    : _gemmaService = gemmaService;

  final GemmaService _gemmaService;

  Future<ExtractedIntake> extract(String transcript) async {
    final text = transcript.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(transcript, 'transcript', 'Text is required.');
    }
    final raw = await _gemmaService.infer(
      GemmaRequest(prompt: _prompt(text), maxTokens: 512, temperature: 0),
    );
    final parsed = parseGemmaThinking(raw.text);
    final json = decodeJsonObject(parsed.finalAnswer);
    return ExtractedIntake(
      patientName: _stringField(json['patient_name']),
      villageOrArea: _stringField(json['village_or_area']),
      state: _stringField(json['state']),
      district: _stringField(json['district']),
      age: _intField(json['age']),
      gender: _genderField(json['gender']),
      tobaccoUse: _boolField(json['tobacco_use']),
      tobaccoBrand: _tobaccoBrandField(json),
      chewsPerDay: _intField(json['chews_per_day']),
      yearsUsed: _intField(json['years_used']),
      alcoholUse: _boolField(json['alcohol_use']),
      symptoms: _stringList(json['symptoms']),
      symptomDuration: _stringField(json['symptom_duration']),
      missingFields: _stringList(json['missing_fields']),
      confidence: _doubleField(json['confidence']) ?? 0,
      modelName: raw.modelName,
      rawJson: json,
    );
  }

  String _prompt(String transcript) {
    final payload = {
      'task': 'extract_oral_screening_intake',
      'transcript': transcript,
      'instructions': [
        'Extract only facts explicitly stated by the speaker.',
        'The goal is to prefill required form fields: patient_name, village_or_area, age, gender, tobacco_brand, chews_per_day, years_used, alcohol_use.',
        'Extract patient name from phrases like "patient name is Ram", "name Ram", or "this is Ram".',
        'Extract village_or_area from phrases like "from Chennai", "village is X", or "area is X". If a city is spoken, use it as village_or_area.',
        'Do not infer phone, PIN code, or ASHA PIN unless directly stated; include them in missing_fields if missing.',
        'If chewing tobacco, showing tobacco, tobacco chewing, gutka, pan masala, betel quid, khaini, or similar use is mentioned, set tobacco_use true and tobacco_brand to the mentioned product. If only tobacco use is clear, use "chewing tobacco".',
        'Never put boolean or placeholder words like false, true, string, unknown, or null into tobacco_brand, symptoms, village_or_area, patient_name, or missing_fields.',
        'If daily chewing is mentioned without a count, set chews_per_day to 1. If frequency is not stated, return null.',
        'If a duration like "past 5 years" is stated for tobacco use, set years_used to 5.',
        'Gender must be one of female, male, other, or null.',
        'If the speaker says "he" for the patient, gender may be male; if "she", gender may be female.',
        'Example transcript: "patient name is Ram he is from Chennai has been chewing tobacco for the past 5 years". Expected: patient_name Ram, village_or_area Chennai, gender male, tobacco_use true, tobacco_brand chewing tobacco, years_used 5.',
        'Return strict JSON only. No markdown.',
      ],
      'output_schema': {
        'patient_name': 'string_or_null',
        'village_or_area': 'string_or_null',
        'state': 'string_or_null',
        'district': 'string_or_null',
        'age': 'integer_or_null',
        'gender': 'female|male|other|null',
        'tobacco_use': 'boolean_or_null',
        'tobacco_brand': 'string_or_null',
        'chews_per_day': 'integer_or_null',
        'years_used': 'integer_or_null',
        'alcohol_use': 'boolean_or_null',
        'symptoms': ['string'],
        'symptom_duration': 'string_or_null',
        'missing_fields': ['string'],
        'confidence': 'number_0_to_1',
      },
    };
    return [
      'You extract structured intake data for an oral cancer screening app.',
      'The output will prefill a form, so be conservative and keep unknown fields null.',
      jsonEncode(payload),
    ].join('\n\n');
  }

  int? _intField(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  double? _doubleField(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  bool? _boolField(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  String? _genderField(Object? value) {
    final normalized = _stringField(value)?.toLowerCase();
    if (normalized == 'female' ||
        normalized == 'male' ||
        normalized == 'other') {
      return normalized;
    }
    return null;
  }

  String? _tobaccoBrandField(Map<String, Object?> json) {
    final brand = _stringField(json['tobacco_brand']);
    if (brand != null) {
      return brand;
    }
    if (_boolField(json['tobacco_use']) == true) {
      return 'chewing tobacco';
    }
    return null;
  }

  String? _stringField(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    final normalized = trimmed.toLowerCase();
    if (trimmed.isEmpty ||
        normalized == 'null' ||
        normalized == 'none' ||
        normalized == 'unknown' ||
        normalized == 'string' ||
        normalized == 'true' ||
        normalized == 'false') {
      return null;
    }
    return trimmed;
  }

  List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return [value.trim()];
    }
    return const [];
  }
}
