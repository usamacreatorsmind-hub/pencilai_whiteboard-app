import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AccountStorageService {
  static const String _fileName = 'recent_accounts.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Get list of all locally saved recent accounts
  Future<List<Map<String, dynamic>>> getRecentAccounts() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        return [];
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      List<dynamic> jsonList = jsonDecode(content);
      return jsonList.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error reading recent accounts: $e');
      return [];
    }
  }

  /// Save or update an account in recent accounts
  Future<void> saveAccount({
    required String uid,
    required String name,
    required String phoneNumber,
    String? classroomName,
    List<String>? subjects,
  }) async {
    try {
      List<Map<String, dynamic>> accounts = await getRecentAccounts();

      // Check if account already exists
      int existingIndex = accounts.indexWhere((acc) => acc['uid'] == uid || acc['phoneNumber'] == phoneNumber);

      Map<String, dynamic> newAccount = {
        'uid': uid,
        'name': name,
        'phoneNumber': phoneNumber,
        'classroomName': classroomName ?? '10',
        'subjects': subjects ?? [],
        'lastSelectedAt': DateTime.now().toIso8601String(),
      };

      if (existingIndex >= 0) {
        accounts[existingIndex] = newAccount;
      } else {
        accounts.insert(0, newAccount);
      }

      final file = await _getFile();
      await file.writeAsString(jsonEncode(accounts));
    } catch (e) {
      debugPrint('Error saving account to local storage: $e');
    }
  }

  /// Remove an account from recent accounts
  Future<void> removeAccount(String identifier) async {
    try {
      List<Map<String, dynamic>> accounts = await getRecentAccounts();
      accounts.removeWhere((acc) => acc['uid'] == identifier || acc['phoneNumber'] == identifier || acc['name'] == identifier);

      final file = await _getFile();
      await file.writeAsString(jsonEncode(accounts));
      await addDeletedUid(identifier);
    } catch (e) {
      debugPrint('Error removing account: $e');
    }
  }

  static const String _deletedFileName = 'deleted_accounts.json';

  Future<File> _getDeletedFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_deletedFileName');
  }

  Future<List<String>> getDeletedUids() async {
    try {
      final file = await _getDeletedFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      List<dynamic> jsonList = jsonDecode(content);
      return jsonList.cast<String>();
    } catch (e) {
      return [];
    }
  }

  Future<void> addDeletedUid(String uid) async {
    if (uid.trim().isEmpty) return;
    try {
      List<String> deleted = await getDeletedUids();
      if (!deleted.contains(uid)) {
        deleted.add(uid);
        final file = await _getDeletedFile();
        await file.writeAsString(jsonEncode(deleted));
      }
    } catch (e) {
      debugPrint('Error saving deleted uid: $e');
    }
  }

  static const String _studentsFileName = 'classroom_students.json';

  Future<File> _getStudentsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_studentsFileName');
  }

  Future<List<Map<String, dynamic>>> getLocalStudents(String teacherId) async {
    try {
      final file = await _getStudentsFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      List<dynamic> jsonList = jsonDecode(content);
      return jsonList.cast<Map<String, dynamic>>().where((s) => s['teacherId'] == teacherId).toList();
    } catch (e) {
      debugPrint('Error reading local students: $e');
      return [];
    }
  }

  Future<void> saveLocalStudent({
    required String teacherId,
    required String classroomName,
    required String studentName,
    required String mobileNumber,
  }) async {
    try {
      final file = await _getStudentsFile();
      List<Map<String, dynamic>> allStudents = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          allStudents = (jsonDecode(content) as List).cast<Map<String, dynamic>>();
        }
      }

      allStudents.add({
        'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
        'teacherId': teacherId,
        'classroomName': classroomName,
        'studentName': studentName,
        'mobileNumber': mobileNumber,
        'createdAt': DateTime.now().toIso8601String(),
      });

      await file.writeAsString(jsonEncode(allStudents));
    } catch (e) {
      debugPrint('Error saving local student: $e');
    }
  }
}
