import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../state/whiteboard_provider.dart';

class QuizQuestion {
  final String question;
  final List<String> options;
  final String correctAnswer;
  int? selectedOptionIndex;
  bool revealAnswer = false;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
  });
}

class AiResultPanel extends StatefulWidget {
  const AiResultPanel({super.key});

  @override
  State<AiResultPanel> createState() => _AiResultPanelState();
}

class _AiResultPanelState extends State<AiResultPanel> {
  double _panelWidth = 440.0;
  String _lastParsedText = '';
  List<QuizQuestion> _cachedQuizQuestions = [];

  List<QuizQuestion> _getQuizQuestions(String text, bool isLoading) {
    if (isLoading) {
      _lastParsedText = '';
      _cachedQuizQuestions = [];
      return [];
    }
    if (text != _lastParsedText) {
      _lastParsedText = text;
      _cachedQuizQuestions = _parseQuiz(text);
    }
    return _cachedQuizQuestions;
  }

  String _getCorrectOptionLetter(String correctAnswerText) {
    if (correctAnswerText.isEmpty) return '';

    // Strip markdown bold, headers, and asterisks
    final clean = correctAnswerText
        .replaceAll('*', '')
        .replaceAll('_', '')
        .replaceAll('#', '')
        .trim();

    // 1. Explicit pattern: "Correct Answer: B" or "Answer: (C)" or "Ans: D"
    final reg1 = RegExp(
      r'(?:correct\s*(?:answer|option)|answer|ans)\s*[:\-]?\s*\(?([A-D])\)?',
      caseSensitive: false,
    );
    final match1 = reg1.firstMatch(clean);
    if (match1 != null) {
      return match1.group(1)!.toUpperCase();
    }

    // 2. Standalone option letter after answer keywords
    final reg2 = RegExp(
      r'(?:correct|answer|ans).{0,20}?\b([A-D])\b',
      caseSensitive: false,
    );
    final match2 = reg2.firstMatch(clean);
    if (match2 != null) {
      return match2.group(1)!.toUpperCase();
    }

    // 3. Isolated letter match (e.g. "Option B")
    final reg3 = RegExp(r'\b([A-D])\b', caseSensitive: false);
    final matches = reg3.allMatches(clean);
    if (matches.isNotEmpty) {
      for (var m in matches) {
        final letter = m.group(1)!.toUpperCase();
        if (['A', 'B', 'C', 'D'].contains(letter)) {
          return letter;
        }
      }
    }

    return '';
  }

  List<QuizQuestion> _parseQuiz(String text) {
    List<QuizQuestion> questions = [];
    final lines = text.split('\n');
    String currentQ = '';
    List<String> currentOpts = [];
    String currentAns = '';

    void addCurrentQuestion() {
      if (currentQ.isNotEmpty && currentOpts.isNotEmpty) {
        questions.add(
          QuizQuestion(
            question: currentQ.trim(),
            options: List.from(currentOpts),
            correctAnswer: currentAns.trim(),
          ),
        );
      }
      currentQ = '';
      currentOpts.clear();
      currentAns = '';
    }

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final cleanLine = trimmed
          .replaceAll('**', '')
          .replaceAll('__', '')
          .replaceAll('#', '')
          .trim();

      // Is new question header? (e.g., 1. What is..., Question 1: ...)
      if (RegExp(r'^(?:question\s*)?\d+[.)]', caseSensitive: false)
          .hasMatch(cleanLine)) {
        addCurrentQuestion();
        currentQ = cleanLine;
      }
      // Is option line? (e.g., A. ..., A) ..., * A) ...)
      else if (RegExp(r'^[*-]?\s*([A-D])[.)]\s*(.*)', caseSensitive: false)
          .hasMatch(cleanLine)) {
        final match = RegExp(r'^[*-]?\s*([A-D])[.)]\s*(.*)',
                caseSensitive: false)
            .firstMatch(cleanLine);
        if (match != null) {
          final letter = match.group(1)!.toUpperCase();
          final optText = match.group(2)!.trim();
          currentOpts.add('$letter. $optText');
        } else {
          currentOpts.add(cleanLine);
        }
      }
      // Is answer line? (e.g., Correct Answer: B, Answer: C)
      else if (RegExp(
              r'(?:correct\s*(?:answer|option)|answer|ans)\s*[:\-]',
              caseSensitive: false)
          .hasMatch(cleanLine)) {
        currentAns = cleanLine;
      }
      // Continuation of question or answer
      else {
        if (currentOpts.isEmpty && currentAns.isEmpty) {
          currentQ = currentQ.isEmpty ? cleanLine : '$currentQ $cleanLine';
        } else if (currentAns.isNotEmpty) {
          currentAns = '$currentAns $cleanLine';
        }
      }
    }
    addCurrentQuestion();
    return questions;
  }

  Widget _buildFormattedTextView(String text) {
    final lines = text.split('\n');
    List<Widget> widgets = [];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      String cleanLine = line
          .replaceAll(RegExp(r'^#+\s*'), '')
          .replaceAll('**', '')
          .replaceAll('__', '');

      if (line.startsWith('###') ||
          line.startsWith('##') ||
          line.startsWith('#') ||
          line.toLowerCase().contains('assignment') ||
          line.toLowerCase().contains('homework')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              cleanLine,
              style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else if (line.startsWith('*') ||
          line.startsWith('-') ||
          line.startsWith('•') ||
          RegExp(r'^\d+[\.\)]').hasMatch(line)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ',
                    style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    cleanLine,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              cleanLine,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14.5, height: 1.5),
            ),
          ),
        );
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WhiteboardProvider>(
      builder: (context, provider, child) {
        if (!provider.isAiPanelOpen) return const SizedBox.shrink();

        final screenWidth = MediaQuery.of(context).size.width;
        final isQuiz = provider.aiTitle.toLowerCase().contains('quiz');
        final quizQuestions = isQuiz
            ? _getQuizQuestions(provider.aiResultText, provider.isAiLoading)
            : <QuizQuestion>[];

        int answeredCount =
            quizQuestions.where((q) => q.selectedOptionIndex != null).length;
        int correctCount = quizQuestions.where((q) {
          if (q.selectedOptionIndex == null) return false;
          final correct = _getCorrectOptionLetter(q.correctAnswer);
          final selectedOpt = q.options[q.selectedOptionIndex!];
          final selectedLetter =
              selectedOpt.isNotEmpty ? selectedOpt[0].toUpperCase() : '';
          return selectedLetter == correct;
        }).length;

        return Positioned(
          top: 20,
          right: 0,
          bottom: 75,
          width: _panelWidth + 24,
          child: Row(
            children: [
              // Left edge drag handle with visible Grip Icon
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _panelWidth = (_panelWidth - details.delta.dx)
                        .clamp(360.0, screenWidth - 100);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Container(
                    width: 24,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF232533),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(-2, 0),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            LucideIcons.gripVertical,
                            color: Color(0xFF38BDF8),
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Material(
                  color: const Color(0xFF1E202B),
                  elevation: 24,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                      ),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF232533),
                              border: Border(
                                  bottom: BorderSide(
                                      color: Colors.white
                                          .withValues(alpha: 0.08))),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(LucideIcons.sparkles,
                                        color: Color(0xFF38BDF8), size: 18),
                                    const SizedBox(width: 10),
                                    Text(
                                      provider.aiTitle.isNotEmpty
                                          ? provider.aiTitle
                                          : 'AI Assistant',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: () => provider.toggleAiPanel(false),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.08),
                                        shape: BoxShape.circle),
                                    child: const Icon(LucideIcons.x,
                                        color: Colors.white70, size: 18),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Content Body
                          Expanded(
                            child: provider.isAiLoading
                                ? const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(
                                            color: Color(0xFF38BDF8)),
                                        SizedBox(height: 16),
                                        Text('Generating Quick Quiz...',
                                            style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14)),
                                      ],
                                    ),
                                  )
                                : isQuiz && quizQuestions.isNotEmpty
                                    ? ListView.builder(
                                        padding: const EdgeInsets.all(20),
                                        itemCount: quizQuestions.length + 1,
                                        itemBuilder: (context, index) {
                                          if (index == 0) {
                                            // Quiz Score & Action Control Bar
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                  bottom: 16),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981)
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: const Color(0xFF10B981)
                                                      .withValues(alpha: 0.3),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        LucideIcons
                                                            .trophy,
                                                        color:
                                                            Color(0xFF34D399),
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        'Score: $correctCount / ${quizQuestions.length}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        '($answeredCount answered)',
                                                        style: const TextStyle(
                                                          color: Colors.white60,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Row(
                                                    children: [
                                                      InkWell(
                                                        onTap: () {
                                                          setState(() {
                                                            for (var q
                                                                in quizQuestions) {
                                                              q.revealAnswer =
                                                                  true;
                                                            }
                                                          });
                                                        },
                                                        child: const Padding(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  horizontal:
                                                                      6,
                                                                  vertical: 4),
                                                          child: Text(
                                                            'Show All',
                                                            style: TextStyle(
                                                              color: Color(
                                                                  0xFF38BDF8),
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      InkWell(
                                                        onTap: () {
                                                          setState(() {
                                                            for (var q
                                                                in quizQuestions) {
                                                              q.selectedOptionIndex =
                                                                  null;
                                                              q.revealAnswer =
                                                                  false;
                                                            }
                                                          });
                                                        },
                                                        child: const Padding(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  horizontal:
                                                                      6,
                                                                  vertical: 4),
                                                          child: Text(
                                                            'Reset',
                                                            style: TextStyle(
                                                              color: Color(
                                                                  0xFFF87171),
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          }

                                          final qIndex = index - 1;
                                          final q = quizQuestions[qIndex];
                                          final correctLetter =
                                              _getCorrectOptionLetter(
                                                  q.correctAnswer);

                                          return Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 20),
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF262938),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.1)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  '${qIndex + 1}. ${q.question.replaceAll(RegExp(r'^\d+[\.\)]\s*'), '')}',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                                const SizedBox(height: 12),
                                                ...List.generate(
                                                    q.options.length, (optIdx) {
                                                  final opt =
                                                      q.options[optIdx];
                                                  final optLetter =
                                                      opt.isNotEmpty
                                                          ? opt[0].toUpperCase()
                                                          : '';
                                                  final isUserSelected =
                                                      (q.selectedOptionIndex ==
                                                          optIdx);
                                                  final isCorrectOption =
                                                      (optLetter ==
                                                          correctLetter);

                                                  // Styling based on answer state
                                                  Color bgColor =
                                                      const Color(0xFF1E202B);
                                                  Color borderColor = Colors
                                                      .white
                                                      .withValues(alpha: 0.08);
                                                  Color textColor =
                                                      Colors.white70;
                                                  Widget? trailingIcon;

                                                  if (q.revealAnswer) {
                                                    if (isCorrectOption) {
                                                      bgColor = const Color(
                                                              0xFF10B981)
                                                          .withValues(
                                                              alpha: 0.2);
                                                      borderColor = const Color(
                                                          0xFF10B981);
                                                      textColor = const Color(
                                                          0xFF34D399);
                                                      trailingIcon = const Icon(
                                                        LucideIcons
                                                            .checkCircle2,
                                                        color: Color(
                                                            0xFF34D399),
                                                        size: 16,
                                                      );
                                                    } else if (isUserSelected) {
                                                      bgColor = const Color(
                                                              0xFFEF4444)
                                                          .withValues(
                                                              alpha: 0.2);
                                                      borderColor = const Color(
                                                          0xFFEF4444);
                                                      textColor = const Color(
                                                          0xFFF87171);
                                                      trailingIcon = const Icon(
                                                        LucideIcons.xCircle,
                                                        color: Color(
                                                            0xFFF87171),
                                                        size: 16,
                                                      );
                                                    }
                                                  } else if (isUserSelected) {
                                                    bgColor = const Color(
                                                            0xFF2563EB)
                                                        .withValues(alpha: 0.3);
                                                    borderColor = const Color(
                                                        0xFF38BDF8);
                                                    textColor = Colors.white;
                                                  }

                                                  return GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        q.selectedOptionIndex =
                                                            optIdx;
                                                        // Automatically check answer on tap for interactive learning feedback
                                                        q.revealAnswer = true;
                                                      });
                                                    },
                                                    child: AnimatedContainer(
                                                      duration: const Duration(
                                                          milliseconds: 150),
                                                      margin:
                                                          const EdgeInsets.only(
                                                              bottom: 8),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 14,
                                                          vertical: 10),
                                                      decoration: BoxDecoration(
                                                        color: bgColor,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                10),
                                                        border: Border.all(
                                                          color: borderColor,
                                                          width: (q.revealAnswer &&
                                                                  (isCorrectOption ||
                                                                      isUserSelected))
                                                              ? 1.5
                                                              : (isUserSelected
                                                                  ? 1.5
                                                                  : 1),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              opt,
                                                              style: TextStyle(
                                                                color:
                                                                    textColor,
                                                                fontSize: 14,
                                                                fontWeight: (isCorrectOption ||
                                                                        isUserSelected)
                                                                    ? FontWeight
                                                                        .bold
                                                                    : FontWeight
                                                                        .normal,
                                                              ),
                                                            ),
                                                          ),
                                                          if (trailingIcon !=
                                                              null)
                                                            trailingIcon,
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }),
                                                const SizedBox(height: 8),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    TextButton.icon(
                                                      onPressed: () {
                                                        setState(() {
                                                          q.revealAnswer =
                                                              !q.revealAnswer;
                                                        });
                                                      },
                                                      icon: Icon(
                                                        q.revealAnswer
                                                            ? LucideIcons.eyeOff
                                                            : LucideIcons.eye,
                                                        size: 14,
                                                        color: const Color(
                                                            0xFF38BDF8),
                                                      ),
                                                      label: Text(
                                                        q.revealAnswer
                                                            ? 'Hide Answer'
                                                            : 'Show Answer',
                                                        style: const TextStyle(
                                                          color: Color(
                                                              0xFF38BDF8),
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    if (q.revealAnswer &&
                                                        q.correctAnswer
                                                            .isNotEmpty)
                                                      Text(
                                                        q.correctAnswer,
                                                        style: const TextStyle(
                                                          color: Color(
                                                              0xFF34D399),
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      )
                                    : _buildFormattedTextView(
                                        provider.aiResultText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
