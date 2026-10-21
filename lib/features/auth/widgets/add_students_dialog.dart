import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class AddStudentsDialog extends StatelessWidget {
  const AddStudentsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AddStudentManuallyDialog.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return const AddStudentManuallyDialog();
  }
}

class AddStudentManuallyDialog extends StatefulWidget {
  const AddStudentManuallyDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const AddStudentManuallyDialog(),
    );
  }

  @override
  State<AddStudentManuallyDialog> createState() => _AddStudentManuallyDialogState();
}

class _AddStudentManuallyDialogState extends State<AddStudentManuallyDialog> {
  final List<Map<String, TextEditingController>> _studentRows = [
    {
      'name': TextEditingController(),
      'phone': TextEditingController(),
    }
  ];

  @override
  void dispose() {
    for (var row in _studentRows) {
      row['name']?.dispose();
      row['phone']?.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _studentRows.add({
        'name': TextEditingController(),
        'phone': TextEditingController(),
      });
    });
  }

  void _removeRow(int index) {
    if (_studentRows.length > 1) {
      setState(() {
        final removed = _studentRows.removeAt(index);
        removed['name']?.dispose();
        removed['phone']?.dispose();
      });
    }
  }

  void _saveStudents(AuthProvider auth) async {
    bool allValid = true;
    for (var row in _studentRows) {
      if (row['name']!.text.trim().isEmpty) {
        allValid = false;
        break;
      }
    }

    if (!allValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.redAccent, content: Text('Student name cannot be empty')),
      );
      return;
    }

    bool success = true;
    int addedCount = 0;
    for (var row in _studentRows) {
      String name = row['name']!.text.trim();
      String phone = row['phone']!.text.trim();
      if (name.isNotEmpty) {
        bool res = await auth.addStudent(studentName: name, mobileNumber: phone);
        if (res) {
          addedCount++;
        } else {
          success = false;
        }
      }
    }

    if (success && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text('$addedCount student(s) added successfully! Total in classroom: ${auth.studentCount}'),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.redAccent, content: Text('Failed to add some students')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Dialog(
      backgroundColor: const Color(0xFF262838),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 1),
      ),
      child: Container(
        width: 580,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add Students manually',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, color: Colors.grey, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Scrollable Student Rows Area
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Labels
                    Row(
                      children: const [
                        Expanded(
                          child: Text('Student Name *', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text('Student / Parent Mobile No. *', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Student Rows List
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _studentRows.length,
                      itemBuilder: (context, index) {
                        final row = _studentRows[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            children: [
                              // Name Field
                              Expanded(
                                child: TextField(
                                  controller: row['name'],
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. Full Name',
                                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                                    filled: true,
                                    fillColor: const Color(0xFF383B52),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Phone Field with +91
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF383B52),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Row(
                                    children: [
                                      const Text('🇮🇳 +91', style: TextStyle(color: Colors.white, fontSize: 13)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: row['phone'],
                                          style: const TextStyle(color: Colors.white, fontSize: 14),
                                          keyboardType: TextInputType.phone,
                                          decoration: const InputDecoration(
                                            hintText: '80350XXXXX',
                                            hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Remove Row Button (if > 1 row)
                              if (_studentRows.length > 1) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  onPressed: () => _removeRow(index),
                                  icon: const Icon(LucideIcons.trash2, color: Colors.redAccent, size: 18),
                                  tooltip: 'Remove',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),

                    // Add More Button
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addRow,
                        icon: const Icon(LucideIcons.userPlus, size: 16, color: Color(0xFF38BDF8)),
                        label: const Text('Add more', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // Fixed Bottom Save Button
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _saveStudents(auth),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save Students', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
