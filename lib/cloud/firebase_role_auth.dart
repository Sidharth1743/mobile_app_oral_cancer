import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth/role_auth.dart';

class FirebaseUserProfile {
  const FirebaseUserProfile({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.active,
    this.email,
    this.mobile,
    this.state,
    this.district,
  });

  final String uid;
  final String displayName;
  final AppRole role;
  final bool active;
  final String? email;
  final String? mobile;
  final String? state;
  final String? district;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'displayName': displayName,
    'role': const AppRoleCodec().toName(role),
    'active': active,
    'email': email,
    'mobile': mobile,
    'state': state,
    'district': district,
  };

  factory FirebaseUserProfile.fromJson(Map<String, Object?> json) {
    return FirebaseUserProfile(
      uid: json['uid'] as String,
      displayName: json['displayName'] as String? ?? '',
      role: const AppRoleCodec().fromName(json['role'] as String),
      active: json['active'] as bool? ?? false,
      email: json['email'] as String?,
      mobile: json['mobile'] as String?,
      state: json['state'] as String?,
      district: json['district'] as String?,
    );
  }
}

class FirebaseRoleAuthService {
  FirebaseRoleAuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<FirebaseUserProfile> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = credential.user?.uid;
    if (uid == null) {
      throw StateError('Firebase login did not return a user.');
    }
    return profileForUid(uid);
  }

  Future<FirebaseUserProfile> currentProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No Firebase user is signed in.');
    }
    return profileForUid(user.uid);
  }

  Future<FirebaseUserProfile> profileForUid(String uid) async {
    final snapshot = await _firestore.doc('users/$uid').get();
    final data = snapshot.data();
    if (data == null) {
      throw StateError('No role profile exists for user $uid.');
    }
    final profile = FirebaseUserProfile.fromJson(
      Map<String, Object?>.from(data),
    );
    if (!profile.active) {
      await _auth.signOut();
      throw StateError('User profile is disabled.');
    }
    return profile;
  }

  Future<void> signOut() => _auth.signOut();
}
