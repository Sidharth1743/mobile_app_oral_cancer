import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

class FirebaseBootstrap {
  const FirebaseBootstrap();

  static bool isInitialized = false;

  Future<bool> initialize() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      isInitialized = true;
      return true;
    } on UnsupportedError catch (error) {
      debugPrint('Firebase skipped on this platform: $error');
      isInitialized = false;
      return false;
    } on FirebaseException catch (error) {
      if (error.code == 'duplicate-app') {
        isInitialized = true;
        return true;
      }
      rethrow;
    }
  }
}
