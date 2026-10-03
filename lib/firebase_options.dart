// Firebase project budgetmate-4224f (same project as the BudgetMate web app).
// These values identify the project; they are not secrets. Access is enforced by
// Firestore rules and App Check.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('BudgetMate mobile supports Android and iOS only.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA0MgoKaKx2LxzLorQvF0oLzowJPe2ad-I',
    appId: '1:713587752268:android:9b986f5fc3ab49d816a3e9',
    messagingSenderId: '713587752268',
    projectId: 'budgetmate-4224f',
    storageBucket: 'budgetmate-4224f.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAKenOoS__xPdl0elj2PSxaPQbmDcJk6Dc',
    appId: '1:713587752268:ios:b7a510cd9cb32b3e16a3e9',
    messagingSenderId: '713587752268',
    projectId: 'budgetmate-4224f',
    storageBucket: 'budgetmate-4224f.firebasestorage.app',
    iosClientId: '713587752268-v0voopvaq67oc29j3kviu70eusm4qhf6.apps.googleusercontent.com',
    iosBundleId: 'com.budgetmate.mobileApp',
  );
}
