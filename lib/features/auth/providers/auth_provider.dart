import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../services/teacher_firestore_service.dart';
import '../services/account_storage_service.dart';

enum OnboardingStep { phoneInput, otpVerify, accountDetails, createClassroom, completed }

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TeacherFirestoreService _firestoreService = TeacherFirestoreService();
  final AccountStorageService _accountStorage = AccountStorageService();

  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  OnboardingStep _currentStep = OnboardingStep.phoneInput;
  String? _teacherName;
  String? _phoneNumber;
  String? _email;
  bool _isEmailLogin = false;
  String? _activeClassroomName;
  List<String> _activeClassroomSubjects = [];
  List<String> _masterSubjects = TeacherFirestoreService.defaultSubjects;
  List<Map<String, dynamic>> _recentAccounts = [];
  List<Map<String, dynamic>> _students = [];

  User? get user => _user;
  bool get isLoggedIn => _currentStep == OnboardingStep.completed && _teacherName != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get phoneNumber => _phoneNumber;
  String? get email => _email;
  bool get isEmailLogin => _isEmailLogin;
  OnboardingStep get currentStep => _currentStep;
  String? get teacherName => _teacherName ?? _user?.displayName;
  String? get activeClassroomName => _activeClassroomName;
  List<String> get activeClassroomSubjects => List.unmodifiable(_activeClassroomSubjects);
  List<String> get masterSubjects => List.unmodifiable(_masterSubjects);
  List<Map<String, dynamic>> get recentAccounts => List.unmodifiable(_recentAccounts);
  List<Map<String, dynamic>> get students => List.unmodifiable(_students);
  int get studentCount => _students.length;

  String get currentUid {
    if (_user?.uid != null && _user!.uid.isNotEmpty) return _user!.uid;
    if (_phoneNumber != null && _phoneNumber!.isNotEmpty) return _phoneNumber!;
    if (_teacherName != null && _teacherName!.isNotEmpty) return _teacherName!;
    return 'local_teacher';
  }

  Future<void> loadStudents() async {
    String uid = currentUid;
    _students = await _firestoreService.getStudents(uid);
    notifyListeners();
  }

  Future<bool> addStudent({required String studentName, required String mobileNumber}) async {
    String uid = currentUid;
    bool success = await _firestoreService.addStudent(
      teacherId: uid,
      classroomName: _activeClassroomName ?? '10',
      studentName: studentName,
      mobileNumber: mobileNumber,
    );
    if (success) {
      await loadStudents();
    }
    return success;
  }

  String get displayName {
    if (!isLoggedIn) return 'GUEST';
    if (_teacherName != null && _teacherName!.trim().isNotEmpty) {
      return _teacherName!.trim().toUpperCase();
    }
    if (_user?.displayName != null && _user!.displayName!.trim().isNotEmpty) {
      return _user!.displayName!.trim().toUpperCase();
    }
    if (_user?.phoneNumber != null && _user!.phoneNumber!.isNotEmpty) {
      return _user!.phoneNumber!;
    }
    return 'TEACHER';
  }

  AuthProvider() {
    _initAuthListener();
    fetchMasterSubjects();
    loadRecentAccounts();
  }

  bool _hasLoadedRecentAccounts = false;
  bool get hasLoadedRecentAccounts => _hasLoadedRecentAccounts;

  Future<void> loadRecentAccounts() async {
    // 1. Load local recent accounts
    List<Map<String, dynamic>> localAccounts = await _accountStorage.getRecentAccounts();

    // 2. Fetch remote teacher profiles from Firestore `Users`/`users` collections
    List<Map<String, dynamic>> remoteProfiles = await _firestoreService.getAllTeacherProfiles();

    // 3. Merge local accounts and remote profiles
    Map<String, Map<String, dynamic>> mergedMap = {};

    for (var acc in localAccounts) {
      String key = acc['uid'] ?? acc['phoneNumber'] ?? acc['name'];
      mergedMap[key] = acc;
    }

    for (var prof in remoteProfiles) {
      String key = prof['uid'] ?? prof['phoneNumber'] ?? prof['name'];
      if (mergedMap.containsKey(key)) {
        mergedMap[key] = {...mergedMap[key]!, ...prof};
      } else {
        mergedMap[key] = {
          'uid': prof['uid'] ?? '',
          'name': prof['name'] ?? 'Teacher',
          'phoneNumber': prof['phoneNumber'] ?? '',
          'classroomName': prof['classroomName'] ?? '10',
          'subjects': prof['subjects'] ?? [],
          'lastSelectedAt': prof['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
        };
      }
    }

    _recentAccounts = mergedMap.values.toList();
    List<String> deletedUids = await _accountStorage.getDeletedUids();
    _recentAccounts = _recentAccounts.where((acc) {
      String uid = acc['uid'] ?? '';
      String phone = acc['phoneNumber'] ?? '';
      String name = acc['name'] ?? '';
      return !deletedUids.contains(uid) && !deletedUids.contains(phone) && !deletedUids.contains(name);
    }).toList();

    _recentAccounts.sort((a, b) {
      String timeA = a['lastSelectedAt'] ?? '';
      String timeB = b['lastSelectedAt'] ?? '';
      return timeB.compareTo(timeA);
    });

    _hasLoadedRecentAccounts = true;
    notifyListeners();
  }

  void _initAuthListener() {
    _auth.authStateChanges().listen((User? user) async {
      _user = user;
      await loadRecentAccounts();

      if (user != null) {
        _phoneNumber = user.phoneNumber;
        _teacherName = user.displayName;
        await _checkAndRestoreTeacherData(user.uid);
      } else {
        // Do not auto-select recent account; let the Select Your Account dialog show up
        _teacherName = null;
        _activeClassroomName = null;
        _activeClassroomSubjects = [];
        _currentStep = OnboardingStep.phoneInput;
      }
      notifyListeners();
    });
  }

  Future<void> fetchMasterSubjects() async {
    List<String> subjects = await _firestoreService.fetchMasterSubjects();
    if (subjects.isNotEmpty) {
      _masterSubjects = subjects;
      notifyListeners();
    }
  }

  Future<void> _checkAndRestoreTeacherData(String uid) async {
    try {
      final profile = await _firestoreService.getTeacherProfile(uid);
      if (profile != null && profile['name'] != null) {
        _teacherName = profile['name'];

        final classrooms = await _firestoreService.getTeacherClassrooms(uid);
        if (classrooms.isNotEmpty) {
          final firstClassroom = classrooms.first;
          _activeClassroomName = firstClassroom['classroomName'];
          _activeClassroomSubjects = List<String>.from(firstClassroom['subjects'] ?? []);
          _currentStep = OnboardingStep.completed;
          await loadStudents();
        } else {
          _currentStep = OnboardingStep.createClassroom;
        }
      } else {
        // Fallback to local recent accounts if Firestore returned null
        final matchedLocal = _recentAccounts.firstWhere((acc) => acc['uid'] == uid || acc['phoneNumber'] == _phoneNumber, orElse: () => {});

        if (matchedLocal.isNotEmpty) {
          _teacherName = matchedLocal['name'];
          _activeClassroomName = matchedLocal['classroomName'];
          _activeClassroomSubjects = List<String>.from(matchedLocal['subjects'] ?? []);
          _currentStep = OnboardingStep.completed;
        } else {
          _currentStep = OnboardingStep.accountDetails;
        }
      }
    } catch (e) {
      debugPrint('Error restoring teacher data: $e');
      _currentStep = OnboardingStep.accountDetails;
    }
  }

  void selectAccount(Map<String, dynamic> account) {
    _teacherName = account['name'];
    _phoneNumber = account['phoneNumber'];
    _activeClassroomName = account['classroomName'];
    _activeClassroomSubjects = List<String>.from(account['subjects'] ?? []);
    _currentStep = OnboardingStep.completed;

    _accountStorage.saveAccount(
      uid: account['uid'] ?? 'local_${DateTime.now().millisecondsSinceEpoch}',
      name: _teacherName!,
      phoneNumber: _phoneNumber ?? '',
      classroomName: _activeClassroomName,
      subjects: _activeClassroomSubjects,
    );

    loadRecentAccounts();
    loadStudents();
    notifyListeners();
  }

  Future<void> removeAccount(String identifier) async {
    await _accountStorage.removeAccount(identifier);
    _recentAccounts.removeWhere((acc) => acc['uid'] == identifier || acc['phoneNumber'] == identifier || acc['name'] == identifier);
    await loadRecentAccounts();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void resetOnboarding() {
    _errorMessage = null;
    _isLoading = false;
    _isEmailLogin = false;
    _email = null;
    _phoneNumber = null;
    _currentStep = OnboardingStep.phoneInput;
    notifyListeners();
  }

  void editDestination() {
    _errorMessage = null;
    _isLoading = false;
    _currentStep = OnboardingStep.phoneInput;
    notifyListeners();
  }

  Future<bool> sendEmailOtp(String emailInput) async {
    _isLoading = true;
    _errorMessage = null;
    _email = emailInput.trim();
    _isEmailLogin = true;
    _currentStep = OnboardingStep.otpVerify;
    notifyListeners();

    try {
      final response = await http
          .post(
            Uri.parse('https://asia-south1-pencilaiboardapp.cloudfunctions.net/sendMsg91EmailOtp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': _email}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      _isLoading = false;
      if (response.statusCode == 200 && data['success'] == true) {
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['error'] ?? 'Failed to send Email OTP';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to connect to Email OTP service: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyEmailOtp(String otpCode) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http
          .post(
            Uri.parse('https://asia-south1-pencilaiboardapp.cloudfunctions.net/verifyMsg91EmailOtp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': _email, 'otp': otpCode.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      _isLoading = false;

      if (response.statusCode == 200 && data['success'] == true) {
        final String? uid = data['uid'] ?? 'email_${_email?.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

        if (_auth.currentUser == null) {
          try {
            await _auth.signInAnonymously();
          } catch (_) {}
        }
        _user = _auth.currentUser;

        await _checkAndRestoreTeacherData(uid!);
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['error'] ?? 'Invalid OTP entered';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Verification failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> resendEmailOtp() async {
    if (_email == null || _email!.isEmpty) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http
          .post(
            Uri.parse('https://asia-south1-pencilaiboardapp.cloudfunctions.net/resendMsg91EmailOtp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': _email}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      _isLoading = false;
      return response.statusCode == 200 && data['success'] == true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to resend Email OTP: $e';
      notifyListeners();
      return false;
    }
  }


  Future<bool> sendOtp(String phoneInput) async {
    _isLoading = true;
    _errorMessage = null;

    String formattedPhone = phoneInput.trim();
    if (formattedPhone.startsWith('+91')) {
      formattedPhone = formattedPhone.substring(3);
    } else if (formattedPhone.startsWith('+')) {
      formattedPhone = formattedPhone.substring(1);
    }
    _phoneNumber = '+91$formattedPhone';

    _currentStep = OnboardingStep.otpVerify;
    notifyListeners();

    try {
      final response = await http
          .post(
            Uri.parse('https://asia-south1-pencilaiboardapp.cloudfunctions.net/sendMsg91Otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'mobile': formattedPhone}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      _isLoading = false;
      if (response.statusCode == 200 && data['success'] == true) {
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['error'] ?? 'Failed to send OTP via MSG91';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to connect to OTP service: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyOtp(String smsCode) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String cleanPhone = (_phoneNumber ?? '').replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.startsWith('91') && cleanPhone.length > 10) {
        cleanPhone = cleanPhone.substring(cleanPhone.length - 10);
      }

      final response = await http
          .post(
            Uri.parse('https://asia-south1-pencilaiboardapp.cloudfunctions.net/verifyMsg91Otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'mobile': cleanPhone, 'otp': smsCode.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      _isLoading = false;

      if (response.statusCode == 200 && data['success'] == true) {
        final String? uid = data['uid'] ?? 'phone_$cleanPhone';

        if (_auth.currentUser == null) {
          try {
            await _auth.signInAnonymously();
          } catch (_) {}
        }
        _user = _auth.currentUser;

        await _checkAndRestoreTeacherData(uid!);

        notifyListeners();
        return true;
      } else {
        _errorMessage = data['error'] ?? 'Invalid OTP entered';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Verification failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> resendOtp() async {
    _errorMessage = null;
    notifyListeners();
    try {
      String cleanPhone = (_phoneNumber ?? '').replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.startsWith('91') && cleanPhone.length > 10) {
        cleanPhone = cleanPhone.substring(cleanPhone.length - 10);
      }

      final response = await http
          .post(
            Uri.parse('https://asia-south1-pencilaiboardapp.cloudfunctions.net/resendMsg91Otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'mobile': cleanPhone}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return true;
      } else {
        _errorMessage = data['error'] ?? 'Failed to resend OTP';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Failed to resend OTP: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> saveTeacherProfile(String name) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String cleanName = name.trim();
      String uid = _user?.uid ?? 'local_${DateTime.now().millisecondsSinceEpoch}';

      if (_user != null) {
        try {
          await _user!.updateDisplayName(cleanName);
          await _user!.reload();
          _user = _auth.currentUser;
        } catch (_) {}

        await _firestoreService.saveTeacherProfile(uid: uid, name: cleanName, phoneNumber: _phoneNumber ?? _user!.phoneNumber ?? '');
      }

      _teacherName = cleanName;

      await _accountStorage.saveAccount(uid: uid, name: cleanName, phoneNumber: _phoneNumber ?? '');
      await loadRecentAccounts();

      _isLoading = false;
      _currentStep = OnboardingStep.createClassroom;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to save profile: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> createClassroom(String classroomName, List<String> subjects) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String uid = _user?.uid ?? 'local_${DateTime.now().millisecondsSinceEpoch}';

      // Save teacher profile to Firestore Users and users collections
      await _firestoreService.saveTeacherProfile(
        uid: uid,
        name: _teacherName ?? _user?.displayName ?? 'Teacher',
        phoneNumber: _phoneNumber ?? _user?.phoneNumber ?? '',
      );

      // Create classroom in Firestore
      await _firestoreService.createClassroom(teacherId: uid, classroomName: classroomName.trim(), subjects: subjects);

      _activeClassroomName = classroomName.trim();
      _activeClassroomSubjects = subjects;

      await _accountStorage.saveAccount(
        uid: uid,
        name: _teacherName ?? 'Teacher',
        phoneNumber: _phoneNumber ?? '',
        classroomName: classroomName.trim(),
        subjects: subjects,
      );
      await loadRecentAccounts();

      _isLoading = false;
      _currentStep = OnboardingStep.completed;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to create classroom: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    await _auth.signOut();
    _user = null;
    _teacherName = null;
    _phoneNumber = null;
    _activeClassroomName = null;
    _activeClassroomSubjects = [];
    _currentStep = OnboardingStep.phoneInput;
    _isLoading = false;
    notifyListeners();
  }
}
