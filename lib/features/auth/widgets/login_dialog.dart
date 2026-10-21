import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'account_selection_dialog.dart';

class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(context: context, barrierDismissible: false, builder: (context) => const LoginDialog());
  }

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  bool _isEmailMode = false;
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();
  final _classroomController = TextEditingController();
  final _subjectController = TextEditingController();
  final _subjectFocusNode = FocusNode();

  final List<String> _selectedSubjects = [];

  Timer? _resendTimer;
  int _resendSeconds = 30;
  bool _canResend = false;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    _classroomController.dispose();
    _subjectController.dispose();
    _subjectFocusNode.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendSeconds = 30;
    _canResend = false;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds > 0) {
        if (mounted) setState(() => _resendSeconds--);
      } else {
        _canResend = true;
        _resendTimer?.cancel();
        if (mounted) setState(() {});
      }
    });
  }

  void _onKeypadTap(String val, AuthProvider auth) {
    if (auth.currentStep == OnboardingStep.phoneInput) {
      if (!_isEmailMode) {
        if (val == 'BACK') {
          if (_phoneController.text.isNotEmpty) {
            _phoneController.text = _phoneController.text.substring(0, _phoneController.text.length - 1);
          }
        } else {
          if (_phoneController.text.length < 10) {
            _phoneController.text += val;
          }
        }
      }
    } else if (auth.currentStep == OnboardingStep.otpVerify) {
      if (val == 'BACK') {
        if (_otpController.text.isNotEmpty) {
          _otpController.text = _otpController.text.substring(0, _otpController.text.length - 1);
        }
      } else {
        if (_otpController.text.length < 4) {
          _otpController.text += val;
        }
      }
    }
    setState(() {});
  }

  void _handleSendOtp(AuthProvider auth) async {
    if (_phoneController.text.trim().length < 10) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(backgroundColor: Colors.redAccent, content: Text('Please enter a valid 10-digit mobile number')));
      return;
    }
    bool success = await auth.sendOtp(_phoneController.text);
    if (success) {
      _startResendTimer();
    }
  }

  void _handleSendEmailOtp(AuthProvider auth) async {
    String email = _emailController.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(backgroundColor: Colors.redAccent, content: Text('Please enter a valid email address')));
      return;
    }
    bool success = await auth.sendEmailOtp(email);
    if (success) {
      _startResendTimer();
    }
  }

  void _handleResendOtp(AuthProvider auth) async {
    if (!_canResend || auth.isLoading) return;
    bool success = await auth.resendOtp();
    if (success && mounted) {
      _startResendTimer();
    }
  }

  void _handleResendEmailOtp(AuthProvider auth) async {
    if (!_canResend || auth.isLoading) return;
    bool success = await auth.resendEmailOtp();
    if (success && mounted) {
      _startResendTimer();
    }
  }

  void _handleVerifyOtp(AuthProvider auth) async {
    if (_otpController.text.trim().length < 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(backgroundColor: Colors.redAccent, content: Text('Please enter 4-digit OTP')));
      return;
    }
    await auth.verifyOtp(_otpController.text);
  }

  void _handleVerifyEmailOtp(AuthProvider auth) async {
    if (_otpController.text.trim().length < 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(backgroundColor: Colors.redAccent, content: Text('Please enter 4-digit OTP')));
      return;
    }
    await auth.verifyEmailOtp(_otpController.text);
  }

  void _handleEditDestination(AuthProvider auth) {
    if (auth.isEmailLogin && auth.email != null) {
      _emailController.text = auth.email!;
      setState(() => _isEmailMode = true);
    } else if (auth.phoneNumber != null) {
      String cleanPhone = auth.phoneNumber!.replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.startsWith('91') && cleanPhone.length > 10) {
        cleanPhone = cleanPhone.substring(cleanPhone.length - 10);
      }
      _phoneController.text = cleanPhone;
      setState(() => _isEmailMode = false);
    }
    _otpController.clear();
    auth.editDestination();
  }

  void _handleSaveProfile(AuthProvider auth) async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(backgroundColor: Colors.redAccent, content: Text('Please enter your name')));
      return;
    }
    await auth.saveTeacherProfile(_nameController.text);
  }

  void _handleCreateClassroom(AuthProvider auth) async {
    if (_classroomController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(backgroundColor: Colors.redAccent, content: Text('Please enter classroom name')));
      return;
    }
    if (_selectedSubjects.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(backgroundColor: Colors.redAccent, content: Text('Please select at least one subject')));
      return;
    }

    bool success = await auth.createClassroom(_classroomController.text, _selectedSubjects);
    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildErrorBanner(AuthProvider auth) {
    if (auth.errorMessage == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade400, width: 1),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle, color: Colors.redAccent, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(auth.errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF262838), // Dark purple/slate background matching screenshots
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 1),
      ),
      elevation: 20,
      child: Container(
        width: 380, // Compact width
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18), // Compact padding
        child: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            switch (auth.currentStep) {
              case OnboardingStep.phoneInput:
                return _buildPhoneInputStep(auth);
              case OnboardingStep.otpVerify:
                return _buildOtpVerifyStep(auth);
              case OnboardingStep.accountDetails:
                return _buildAccountDetailsStep(auth);
              case OnboardingStep.createClassroom:
                return _buildCreateClassroomStep(auth);
              case OnboardingStep.completed:
                return _buildCompletedStep(auth);
            }
          },
        ),
      ),
    );
  }

  // --- STEP 1: SIGN UP / LOGIN (MOBILE / EMAIL + OR LOGIN WITH + KEYPAD) ---
  Widget _buildPhoneInputStep(AuthProvider auth) {
    bool isPhoneValid = _phoneController.text.trim().length >= 10;
    bool isEmailValid = _emailController.text.trim().contains('@') && _emailController.text.trim().contains('.');

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sign up/Login',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Container(
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                padding: const EdgeInsets.all(5),
                child: const Icon(LucideIcons.helpCircle, color: Colors.white70, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _buildErrorBanner(auth),

          if (!_isEmailMode) ...[
            // Label
            Row(
              children: const [
                Text(
                  'Mobile Number ',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                Text(
                  '*',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Input Box with Country Code Dropdown
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF383B52),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isPhoneValid ? const Color(0xFF38BDF8) : Colors.transparent, width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Row(
                children: [
                  // Flag + Country Code
                  Row(
                    children: const [
                      Text('🇮🇳', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 4),
                      Text(
                        '+91',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 2),
                      Icon(LucideIcons.chevronDown, color: Colors.white70, size: 14),
                    ],
                  ),
                  Container(height: 20, width: 1, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 10)),

                  // Phone Field
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      readOnly: true, // Controlled by keypad below
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                      decoration: const InputDecoration(
                        hintText: '80350XXXXX',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Next Button
            SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: auth.isLoading ? null : () => _handleSendOtp(auth),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPhoneValid ? Colors.white : Colors.white24,
                  foregroundColor: isPhoneValid ? Colors.black : Colors.white38,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: auth.isLoading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Next', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),

            // "or login with" Divider & Options
            Row(
              children: const [
                Expanded(child: Divider(color: Colors.white24, thickness: 1)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('or login with', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ),
                Expanded(child: Divider(color: Colors.white24, thickness: 1)),
              ],
            ),
            const SizedBox(height: 12),

            // Icons: Email & Select Account
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Email login button
                GestureDetector(
                  onTap: () => setState(() => _isEmailMode = true),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: const Color(0xFF383B52), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(LucideIcons.mail, color: Colors.white70, size: 18),
                  ),
                ),
                const SizedBox(width: 16),
                // Select Account button
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    AccountSelectionDialog.show(context);
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: const Color(0xFF383B52), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(LucideIcons.users, color: Colors.white70, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildKeypad(auth),
          ] else ...[
            // Email Input Mode
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Email Address *',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                TextButton(
                  onPressed: () => setState(() => _isEmailMode = false),
                  child: const Text('Use Mobile Number', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF383B52),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isEmailValid ? const Color(0xFF38BDF8) : Colors.transparent, width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'teacher@example.com',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                  prefixIcon: Icon(LucideIcons.mail, color: Colors.white54, size: 16),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 18),

            SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: auth.isLoading ? null : () => _handleSendEmailOtp(auth),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEmailValid ? Colors.white : Colors.white24,
                  foregroundColor: isEmailValid ? Colors.black : Colors.white38,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: auth.isLoading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Next', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeypad(AuthProvider auth) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'BACK'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4.0), // Compact gap
          child: Row(
            children: row.map((key) {
              if (key.isEmpty) {
                return const Expanded(child: SizedBox());
              }
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3.0),
                  child: Material(
                    color: const Color(0xFF383B52),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _onKeypadTap(key, auth),
                      child: Container(
                        height: 38, // Compact height
                        alignment: Alignment.center,
                        child: key == 'BACK'
                            ? const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 18)
                            : Text(
                                key,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  // --- STEP 1.5: OTP VERIFICATION ---
  Widget _buildOtpVerifyStep(AuthProvider auth) {
    bool isOtpValid = _otpController.text.trim().length >= 4;
    String destination = auth.isEmailLogin ? (auth.email ?? _emailController.text) : (auth.phoneNumber ?? _phoneController.text);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Enter OTP',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => auth.resetOnboarding(),
                icon: const Icon(LucideIcons.x, color: Colors.white70, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Verification code sent to $destination', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 12),

          _buildErrorBanner(auth),

          TextField(
            controller: _otpController,
            readOnly: true, // Controlled by touch keypad below
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.bold),
            maxLength: 4,
            decoration: InputDecoration(
              counterText: '',
              hintText: '----',
              hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 6),
              filled: true,
              fillColor: const Color(0xFF383B52),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 14),

          SizedBox(
            height: 42,
            child: ElevatedButton(
              onPressed: (auth.isLoading || !isOtpValid)
                  ? null
                  : () => auth.isEmailLogin ? _handleVerifyEmailOtp(auth) : _handleVerifyOtp(auth),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: auth.isLoading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Verify OTP', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => _handleEditDestination(auth),
                child: Text(
                  auth.isEmailLogin ? 'Edit Email' : 'Edit Number',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                ),
              ),
              TextButton(
                onPressed: (!_canResend || auth.isLoading)
                    ? null
                    : () => auth.isEmailLogin ? _handleResendEmailOtp(auth) : _handleResendOtp(auth),
                child: Text(
                  _canResend ? 'Resend OTP' : 'Resend in 0:${_resendSeconds.toString().padLeft(2, '0')}',
                  style: TextStyle(color: _canResend ? const Color(0xFF38BDF8) : Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildKeypad(auth),
        ],
      ),
    );
  }

  // --- STEP 2: ACCOUNT DETAILS (PROFILE SETUP) ---
  Widget _buildAccountDetailsStep(AuthProvider auth) {
    String destinationDisplay = auth.isEmailLogin ? (auth.email ?? _emailController.text) : (auth.phoneNumber ?? _phoneController.text);
    if (!auth.isEmailLogin && destinationDisplay.length > 6) {
      destinationDisplay = '+91-******${destinationDisplay.substring(destinationDisplay.length - 4)}';
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Account details',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Text(
                    destinationDisplay,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.pencil, color: Color(0xFF38BDF8), size: 13),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text("Let's set up your teacher profile", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),

          _buildErrorBanner(auth),

          Container(
            height: 130, // Compact height
            decoration: BoxDecoration(color: const Color(0xFF383B52), borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64, // Compact avatar
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Center(child: Icon(LucideIcons.user, size: 32, color: Colors.white)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Teacher Profile',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Name Input
          const Text(
            'Full Name *',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Enter your full name',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF383B52),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 18),

          // Save Button
          SizedBox(
            height: 42,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : () => _handleSaveProfile(auth),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: auth.isLoading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Continue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 3: CREATE CLASSROOM (AUTOCOMPLETE SUBJECTS + MANUAL ENTRY) ---
  Widget _buildCreateClassroomStep(AuthProvider auth) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create Your Classroom',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('Setup your first classroom and select subjects', style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 12),

          _buildErrorBanner(auth),

          const Text(
            'Classroom / Standard Name *',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _classroomController,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'e.g. Class 10th A or Physics Batch',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF383B52),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Subjects Autocomplete & Manual Entry
          const Text(
            'Select Subjects *',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Autocomplete<String>(
            textEditingController: _subjectController,
            focusNode: _subjectFocusNode,
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<String>.empty();
              }
              return auth.masterSubjects.where((String option) {
                return option.toLowerCase().contains(textEditingValue.text.toLowerCase()) && !_selectedSubjects.contains(option);
              });
            },
            onSelected: (String selection) {
              if (!_selectedSubjects.contains(selection)) {
                setState(() {
                  _selectedSubjects.add(selection);
                  _subjectController.clear();
                });
              }
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Type or search subject...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF383B52),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  suffixIcon: IconButton(
                    icon: const Icon(LucideIcons.plus, color: Color(0xFF38BDF8), size: 18),
                    onPressed: () {
                      final val = _subjectController.text.trim();
                      if (val.isNotEmpty && !_selectedSubjects.contains(val)) {
                        setState(() {
                          _selectedSubjects.add(val);
                          _subjectController.clear();
                        });
                      }
                    },
                  ),
                ),
                onSubmitted: (String val) {
                  val = val.trim();
                  if (val.isNotEmpty && !_selectedSubjects.contains(val)) {
                    setState(() {
                      _selectedSubjects.add(val);
                      _subjectController.clear();
                    });
                  }
                },
              );
            },
          ),

          if (_selectedSubjects.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedSubjects.map((sub) {
                return Chip(
                  backgroundColor: const Color(0xFF38BDF8),
                  label: Text(
                    sub,
                    style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  deleteIcon: const Icon(LucideIcons.x, size: 12, color: Colors.black87),
                  onDeleted: () {
                    setState(() {
                      _selectedSubjects.remove(sub);
                    });
                  },
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 18),

          SizedBox(
            height: 42,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : () => _handleCreateClassroom(auth),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: auth.isLoading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Start Teaching', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 4: COMPLETED (fallback name) ---
  Widget _buildCompletedStep(AuthProvider auth) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(LucideIcons.checkCircle2, color: Colors.greenAccent, size: 54),
        const SizedBox(height: 12),
        const Text(
          'Welcome!',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text('Logged in as ${auth.teacherName ?? 'Teacher'}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Open Whiteboard', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
