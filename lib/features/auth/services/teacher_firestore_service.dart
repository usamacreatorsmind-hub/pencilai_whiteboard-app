import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'account_storage_service.dart';

class TeacherFirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AccountStorageService _accountStorage = AccountStorageService();

  static const List<String> defaultSubjects = [
    'Bio',
    'Accountancy',
    'Hindi',
    'Algebra',
    'Physics',
    'Chemistry',
    'Mathematics',
    'English',
    'Social Studies',
    'Computer Science',
  ];


  /// Fetch master subjects list from Firestore `subjects_master` collection.
  /// If collection is empty, seeds default subjects for seamless first-time usage.
  Future<List<String>> fetchMasterSubjects() async {
    try {
      final querySnapshot = await _firestore.collection('subjects_master').get();

      if (querySnapshot.docs.isEmpty) {
        try {
          // Seed default master subjects into Firestore for future admin modifications
          WriteBatch batch = _firestore.batch();
          for (String subject in defaultSubjects) {
            DocumentReference docRef = _firestore.collection('subjects_master').doc(subject.toLowerCase());
            batch.set(docRef, {'name': subject, 'createdAt': FieldValue.serverTimestamp()});
          }
          await batch.commit();
        } catch (e) {
          debugPrint('Notice: Batch seed failed (check Firestore Security Rules): $e');
        }
        return defaultSubjects;
      }

      List<String> subjects = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return (data['name'] as String?) ?? doc.id;
      }).toList();

      subjects.sort();
      return subjects;
    } catch (e) {
      debugPrint('Notice: Fetching subjects_master failed (using default fallback): $e');
      return defaultSubjects;
    }
  }

  /// Save or update teacher profile details in Firestore under `teachers`, `users`, and `Users` collections
  Future<void> saveTeacherProfile({required String uid, required String name, required String phoneNumber}) async {
    try {
      final profileData = {
        'uid': uid,
        'name': name.trim(),
        'phoneNumber': phoneNumber.trim(),
        'role': 'teacher',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await _firestore.collection('teachers').doc(uid).set(profileData, SetOptions(merge: true));
      await _firestore.collection('users').doc(uid).set(profileData, SetOptions(merge: true));
      await _firestore.collection('Users').doc(uid).set(profileData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving profile to Firestore: $e');
    }
  }

  /// Fetch all teacher profiles from `teachers`, `users`, and `Users` collections
  Future<List<Map<String, dynamic>>> getAllTeacherProfiles() async {
    List<Map<String, dynamic>> allProfiles = [];
    Set<String> processedUids = {};

    for (String colName in ['teachers', 'users', 'Users']) {
      try {
        QuerySnapshot querySnapshot = await _firestore.collection(colName).get();
        for (var doc in querySnapshot.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          String uid = data['uid'] ?? doc.id;
          if (processedUids.contains(uid)) continue;
          processedUids.add(uid);
          data['uid'] = uid;

          try {
            List<Map<String, dynamic>> classrooms = await getTeacherClassrooms(uid);
            if (classrooms.isNotEmpty) {
              data['classroomName'] = classrooms.first['classroomName'];
              data['subjects'] = classrooms.first['subjects'] ?? [];
            }
          } catch (_) {}

          allProfiles.add(data);
        }
      } catch (e) {
        debugPrint('Error fetching profiles from $colName: $e');
      }
    }
    return allProfiles;
  }

  /// Fetch teacher profile data from `teachers`, `users`, or `Users` collection
  Future<Map<String, dynamic>?> getTeacherProfile(String uid) async {
    try {
      for (String colName in ['teachers', 'users', 'Users']) {
        DocumentSnapshot doc = await _firestore.collection(colName).doc(uid).get();
        if (doc.exists && doc.data() != null) {
          return doc.data() as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('Notice: Getting user profile failed: $e');
    }
    return null;
  }

  /// Create a new classroom in Firestore under `classrooms` collection
  Future<String> createClassroom({required String teacherId, required String classroomName, required List<String> subjects}) async {
    try {
      DocumentReference docRef = await _firestore.collection('classrooms').add({
        'teacherId': teacherId,
        'classroomName': classroomName.trim(),
        'subjects': subjects,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } catch (e) {
      debugPrint('Notice: Creating classroom in Firestore failed (check Security Rules): $e');
      return 'local_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Fetch classrooms created by teacher
  Future<List<Map<String, dynamic>>> getTeacherClassrooms(String teacherId) async {
    try {
      QuerySnapshot querySnapshot = await _firestore.collection('classrooms').where('teacherId', isEqualTo: teacherId).get();

      return querySnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Notice: Fetching teacher classrooms failed: $e');
      return [];
    }
  }

  /// Add student to `students` collection in Firestore with local fallback
  Future<bool> addStudent({
    required String teacherId,
    required String classroomName,
    required String studentName,
    required String mobileNumber,
  }) async {
    try {
      await _firestore.collection('students').add({
        'teacherId': teacherId,
        'classroomName': classroomName.trim(),
        'studentName': studentName.trim(),
        'mobileNumber': mobileNumber.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _accountStorage.saveLocalStudent(
        teacherId: teacherId,
        classroomName: classroomName,
        studentName: studentName,
        mobileNumber: mobileNumber,
      );
      return true;
    } catch (e) {
      debugPrint('Firestore addStudent failed (using local storage fallback): $e');
      await _accountStorage.saveLocalStudent(
        teacherId: teacherId,
        classroomName: classroomName,
        studentName: studentName,
        mobileNumber: mobileNumber,
      );
      return true; // Return true so UI never blocks on permission denied
    }
  }

  /// Get students for a teacher / classroom (Firestore + local storage)
  Future<List<Map<String, dynamic>>> getStudents(String teacherId) async {
    List<Map<String, dynamic>> students = [];
    Set<String> uniqueNames = {};

    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('students')
          .where('teacherId', isEqualTo: teacherId)
          .get();

      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        String nameKey = '${data['studentName']}_${data['mobileNumber']}';
        uniqueNames.add(nameKey);
        students.add(data);
      }
    } catch (e) {
      debugPrint('Firestore getStudents failed: $e');
    }

    try {
      List<Map<String, dynamic>> localStudents = await _accountStorage.getLocalStudents(teacherId);
      for (var student in localStudents) {
        String nameKey = '${student['studentName']}_${student['mobileNumber']}';
        if (!uniqueNames.contains(nameKey)) {
          uniqueNames.add(nameKey);
          students.add(student);
        }
      }
    } catch (e) {
      debugPrint('Local getStudents failed: $e');
    }

    return students;
  }
}
