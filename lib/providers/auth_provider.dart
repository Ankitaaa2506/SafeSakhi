import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  User? _firebaseUser;
  AppUser? _appUser;
  bool _isLoading = false;

  User? get firebaseUser => _firebaseUser;
  AppUser? get appUser => _appUser;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _firebaseUser != null;
  bool get hasProfile => _appUser != null;

  AuthProvider() {
    _authService.authStateChanges.listen((User? user) {
      _firebaseUser = user;
      if (user != null) {
        _loadUserDoc(user.uid);
      } else {
        _appUser = null;
        notifyListeners();
      }
    });
  }

  Future<void> _loadUserDoc(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      _appUser = await _firestoreService.getUser(uid);
    } catch (e) {
      debugPrint('Failed to load user doc: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> signInWithGoogle() async {
    _isLoading = true;
    notifyListeners();
    try {
      final credential = await _authService.signInWithGoogle();
      final user = credential.user;
      if (user != null) {
        final appUser = AppUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
          photoUrl: user.photoURL,
          authProvider: 'google',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        _appUser = appUser;
        notifyListeners();
        _firestoreService.upsertUser(appUser).catchError((e) =>
            debugPrint('Background upsertUser failed: $e'));
      }
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _appUser = null;
    _firebaseUser = null;
    notifyListeners();
  }
}
