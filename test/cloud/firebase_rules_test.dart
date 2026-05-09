import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('firebase json points to Firestore and Storage rules', () {
    final source = File('firebase.json').readAsStringSync();

    expect(source, contains('"rules": "firestore.rules"'));
    expect(source, contains('"rules": "storage.rules"'));
  });

  test('Firestore rules deny NGO and research access to patient identity', () {
    final rules = File('firestore.rules').readAsStringSync();

    expect(rules, contains('match /private/patientIdentity'));
    expect(rules, contains('isCaseAsha'));
    expect(rules, contains('isCaseDoctor'));
    expect(
      rules,
      isNot(
        contains(
          r'isNgoCsr(get(/databases/$(database)/documents/cases/$(caseId)).data)',
        ),
      ),
    );
    expect(
      rules,
      isNot(
        contains(
          r'isResearch(get(/databases/$(database)/documents/cases/$(caseId)).data)',
        ),
      ),
    );
  });

  test('Firestore rules block direct identity fields in public case docs', () {
    final rules = File('firestore.rules').readAsStringSync();

    expect(rules, contains('directIdentityKeys'));
    expect(rules, contains('hasNoDirectIdentity(request.resource.data)'));
    expect(rules, contains("'fullName'"));
    expect(rules, contains("'phone'"));
    expect(rules, contains("'pinCode'"));
  });

  test('Storage rules allow image uploads but no broad raw path', () {
    final rules = File('storage.rules').readAsStringSync();

    expect(rules, contains('match /cases/{caseId}/{visitId}/roi/{fileName}'));
    expect(rules, contains("request.resource.contentType == 'image/jpeg'"));
    expect(rules, contains('match /cases/{caseId}/{visitId}/masks/{fileName}'));
    expect(rules, contains("request.resource.contentType == 'image/png'"));
    expect(rules, isNot(contains('/raw/')));
  });
}
