import 'dart:convert';

import 'package:flutter/services.dart';

class IndiaStateLocation {
  const IndiaStateLocation({
    required this.code,
    required this.name,
    required this.districts,
  });

  final String code;
  final String name;
  final List<String> districts;

  Map<String, Object?> toJson() => {
    'code': code,
    'name': name,
    'districts': districts,
  };

  factory IndiaStateLocation.fromJson(Map<String, Object?> json) {
    return IndiaStateLocation(
      code: json['code'] as String,
      name: json['name'] as String,
      districts: List<String>.from(json['districts'] as List),
    );
  }
}

class IndiaLocationCatalog {
  const IndiaLocationCatalog(this.states);

  static const assetPath = 'assets/locations/india_states_districts.json';

  final List<IndiaStateLocation> states;

  List<String> districtsForState(String stateNameOrCode) {
    final normalized = _normalize(stateNameOrCode);
    for (final state in states) {
      if (_normalize(state.name) == normalized ||
          _normalize(state.code) == normalized) {
        return state.districts;
      }
    }
    return const [];
  }

  factory IndiaLocationCatalog.fromJson(Map<String, Object?> json) {
    return IndiaLocationCatalog(
      (json['states'] as List)
          .map(
            (state) => IndiaStateLocation.fromJson(
              Map<String, Object?>.from(state as Map),
            ),
          )
          .toList(),
    );
  }

  static Future<IndiaLocationCatalog> load({
    AssetBundle? bundle,
    String path = assetPath,
  }) async {
    final source = await (bundle ?? rootBundle).loadString(path);
    return IndiaLocationCatalog.fromJson(
      Map<String, Object?>.from(jsonDecode(source) as Map),
    );
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
