import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'class_reminder_service.dart';
import 'push_notification_service.dart';
import '../network/api_client.dart';

class AuthService {
  const AuthService();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  FirebaseFirestore get _database => FirebaseFirestore.instance;

  Stream<User?> get authStateChanges {
    return _auth.authStateChanges();
  }

  Stream<User?> get userChanges {
    return _auth.userChanges();
  }

  User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<AppUserProfile> register({
    required String displayName,
    required String email,
    required String institutionId,
    required String password,
    required String role,
    String? inviteSecret,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedInstitutionId = institutionId.trim().toUpperCase();
    final normalizedRole = role.trim().toLowerCase();

    if (normalizedRole != 'teacher' && normalizedRole != 'student') {
      throw const AuthServiceException(
        'Account role must be either teacher or student.',
      );
    }

    try {
      final registrationPayload = <String, dynamic>{
        'displayName': displayName.trim(),
        'email': normalizedEmail,
        'institutionId': normalizedInstitutionId,
        'password': password,
        'role': normalizedRole,
      };
      if (inviteSecret != null && inviteSecret.trim().isNotEmpty) {
        registrationPayload['inviteSecret'] = inviteSecret.trim();
      }

      await ApiClient.call('registerUser', registrationPayload);

      final credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw const AuthServiceException(
          'The account was created, but sign-in failed.',
        );
      }

      await user.reload();
      final currentUser = _auth.currentUser ?? user;

      if (!currentUser.emailVerified) {
        await currentUser.sendEmailVerification();
      }

      return await loadCurrentProfile();
    } on ApiException catch (error) {
      throw AuthServiceException(error.message);
    } on FirebaseFunctionsException catch (error) {
      throw AuthServiceException(
        error.message ?? 'Registration failed. Please try again.',
      );
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(_authErrorMessage(error));
    }
  }

  Future<AppUserProfile> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      return await loadCurrentProfile();
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(_authErrorMessage(error));
    } on FirebaseException catch (error) {
      throw AuthServiceException(
        error.message ?? 'Your profile could not be loaded.',
      );
    }
  }

  Future<AppUserProfile> loadCurrentProfile() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw const AuthServiceException('You are not signed in.');
    }

    final document = await _database.collection('users').doc(user.uid).get();

    final data = document.data();

    if (!document.exists || data == null) {
      throw const AuthServiceException(
        'No TrackAcademic profile exists for this account.',
      );
    }

    final profile = AppUserProfile.fromMap(user.uid, data);

    if (!profile.isActive) {
      await signOut();

      throw const AuthServiceException('This account has been disabled.');
    }

    return profile;
  }

  Future<AppUserProfile> updateProfile({
    required String displayName,
    String? department,
    String? batch,
    String? section,
    String? semester,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw const AuthServiceException('You are not signed in.');
    }

    final name = displayName.trim();

    if (name.length < 2 || name.length > 80) {
      throw const AuthServiceException(
        'Full name must be between 2 and 80 characters.',
      );
    }

    String? normalize(String? value) {
      final trimmed = value?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    }

    try {
      await _database.collection('users').doc(user.uid).update({
        'displayName': name,
        'department': normalize(department),
        'batch': normalize(batch),
        'section': normalize(section),
        'semester': normalize(semester),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await user.updateDisplayName(name);
      await user.reload();

      return await loadCurrentProfile();
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(_authErrorMessage(error));
    } on FirebaseException catch (error) {
      throw AuthServiceException(
        error.message ?? 'Profile could not be updated.',
      );
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(_authErrorMessage(error));
    }
  }

  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw const AuthServiceException('You are not signed in.');
    }

    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      throw AuthServiceException(_authErrorMessage(error));
    }
  }

  static bool _isRefreshingVerification = false;
  static DateTime? _lastVerificationRefreshTime;

  Future<bool> refreshEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    if (_isRefreshingVerification) {
      debugPrint('[AuthService] Verification refresh already in progress.');
      return _auth.currentUser?.emailVerified ?? false;
    }

    final now = DateTime.now();
    if (_lastVerificationRefreshTime != null &&
        now.difference(_lastVerificationRefreshTime!).inMilliseconds < 1500) {
      return _auth.currentUser?.emailVerified ?? false;
    }

    _isRefreshingVerification = true;
    _lastVerificationRefreshTime = now;

    try {
      // Bound the reload operation
      await user.reload().timeout(const Duration(seconds: 10));
      final currentUser = _auth.currentUser;
      final isVerified = currentUser?.emailVerified ?? false;

      if (isVerified && currentUser != null) {
        // Force refresh the ID token so claims update immediately in rules and API
        await currentUser.getIdToken(true).timeout(const Duration(seconds: 10));

        // Touch Firestore user profile cache
        try {
          await _database.collection('users').doc(currentUser.uid).get();
        } catch (_) {}
      }

      return isVerified;
    } catch (e) {
      debugPrint('[AuthService] Error during verification refresh: $e');
      return _auth.currentUser?.emailVerified ?? false;
    } finally {
      _isRefreshingVerification = false;
    }
  }

  Future<void> signOut() async {
    try {
      await PushNotificationService().unregisterUserDevice();
    } catch (e) {
      debugPrint('[AuthService] Failed to unregister push token: $e');
    }
    try {
      ClassReminderService().stopScheduleSync();
    } catch (_) {}
    return _auth.signOut();
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return 'The email or password is incorrect.';

      case 'invalid-email':
        return 'Enter a valid email address.';

      case 'email-already-in-use':
        return 'An account already exists for this email.';

      case 'weak-password':
        return 'Use a stronger password.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'network-request-failed':
        return 'Check your internet connection and try again.';

      default:
        return error.message ?? 'Authentication failed.';
    }
  }
}

class AppUserProfile {
  final String uid;
  final String displayName;
  final String email;
  final String institutionId;

  /// Legacy metadata from accounts created before
  /// course-scoped permissions were introduced.
  ///
  /// This value is NOT used for authorization.
  final String? role;

  final bool isActive;
  final String? photoUrl;
  final String? department;
  final String? batch;
  final String? section;
  final String? semester;

  const AppUserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.institutionId,
    required this.isActive,
    this.role,
    this.photoUrl,
    this.department,
    this.batch,
    this.section,
    this.semester,
  });

  factory AppUserProfile.fromMap(String uid, Map<String, dynamic> data) {
    return AppUserProfile(
      uid: uid,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      institutionId: data['institutionId'] as String? ?? '',
      role: data['role'] as String?,
      isActive: data['isActive'] as bool? ?? false,
      photoUrl: data['photoUrl'] as String?,
      department: data['department'] as String?,
      batch: data['batch'] as String?,
      section: data['section'] as String?,
      semester: data['semester'] as String?,
    );
  }
}

class AuthServiceException implements Exception {
  final String message;

  const AuthServiceException(this.message);

  @override
  String toString() => message;
}
