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

  QuizQuestion({required this.question, required this.options, required this.correctAnswer});
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

  List<QuizQuestion> _getQuizQuestions(String text) {
    if (text != _lastParsedText) {
      _lastParsedText = text;
      _cachedQuizQuestions = _parseQuiz(text);
    }
    return _cachedQuizQuestions;
  }

  String _getCorrectOptionLetter(String correctAnswerText) {
    final reg = RegExp(r'(?:correct\s*answer|answer)\s*[:\-]?\s*([A-Da-d])', caseSensitive: false);
    final match = reg.firstMatch(correctAnswerText);
    if (match != null) {
      return match.group(1)!.toUpperCase();
    }
    for (var char in ['A', 'B', 'C', 'D']) {
      if (correctAnswerText.toUpperCase().contains(char)) {
        return char;
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

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (RegExp(r'^(\*\*|#)*\s*\d+[\.\)]').hasMatch(line)) {
        if (currentQ.isNotEmpty) {
          questions.add(QuizQuestion(question: currentQ, options: List.from(currentOpts), correctAnswer: currentAns));
          currentOpts.clear();
          currentAns = '';
        }
        currentQ = line.replaceAll(RegExp(r'^\*\*|\*\*$|^#+'), '').trim();
      } else if (RegExp(r'^[A-D][\.\)]', caseSensitive: false).hasMatch(line)) {
        currentOpts.add(line);
      } else if (line.toLowerCase().contains('correct answer') || line.toLowerCase().contains('answer:')) {
        currentAns = line;
      } else {
        if (currentOpts.isEmpty && currentAns.isEmpty) {
          if (currentQ.isEmpty) {
            currentQ = line;
          } else {
            currentQ += ' $line';
          }
        } else if (currentAns.isNotEmpty) {
          currentAns += ' $line';
        }
      }
    }
    if (currentQ.isNotEmpty) {
      questions.add(QuizQuestion(question: currentQ, options: List.from(currentOpts), correctAnswer: currentAns));
    }
    return questions;
  }

  Widget _buildFormattedTextView(String text) {
    final lines = text.split('\n');
    List<Widget> widgets = [];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Robustly remove all markdown bold, headers, and asterisk symbols
      String cleanLine = line
          .replaceAll(RegExp(r'^#+\s*'), '')
          .replaceAll('**', '')
          .replaceAll('__', '');

      if (line.startsWith('###') || line.startsWith('##') || line.startsWith('#') || line.toLowerCase().contains('assignment') || line.toLowerCase().contains('homework')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              cleanLine,
              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else if (line.startsWith('*') || line.startsWith('-') || line.startsWith('•') || RegExp(r'^\d+[\.\)]').hasMatch(line)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• ', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 15, fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    cleanLine,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.5),
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
              style: const TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.5),
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
        final quizQuestions = isQuiz && !provider.isAiLoading ? _getQuizQuestions(provider.aiResultText) : <QuizQuestion>[];

        return Positioned(
          top: 20,
          right: 0,
          bottom: 75,
          width: _panelWidth + 24, // width + drag handle area
          child: Row(
            children: [
              // Left edge drag handle with visible Grip Icon
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _panelWidth = (_panelWidth - details.delta.dx).clamp(360.0, screenWidth - 100);
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
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF232533),
                              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(LucideIcons.sparkles, color: Color(0xFF38BDF8), size: 18),
                                    const SizedBox(width: 10),
                                    Text(
                                      provider.aiTitle.isNotEmpty ? provider.aiTitle : 'AI Assistant',
                                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                // Top-Corner Close Button (X)
                                GestureDetector(
                                  onTap: () => provider.toggleAiPanel(false),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
                                    child: const Icon(LucideIcons.x, color: Colors.white70, size: 18),
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
                                        CircularProgressIndicator(color: Color(0xFF38BDF8)),
                                        SizedBox(height: 16),
                                        Text('Generating AI content...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                      ],
                                    ),
                                  )
                                : isQuiz && quizQuestions.isNotEmpty
                                    ? ListView.builder(
                                        padding: const EdgeInsets.all(20),
                                        itemCount: quizQuestions.length,
                                        itemBuilder: (context, qIndex) {
                                          final q = quizQuestions[qIndex];
                                          final correctLetter = _getCorrectOptionLetter(q.correctAnswer);

                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 20),
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF262938),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Text(
                                                  q.question,
                                                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(height: 12),
                                                ...q.options.map((opt) {
                                                  final optLetter = opt.isNotEmpty ? opt[0].toUpperCase() : '';
                                                  final isCorrect = q.revealAnswer && optLetter == correctLetter;
                                                  final isSelected = q.selectedOptionIndex == q.options.indexOf(opt);

                                                  return GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        q.selectedOptionIndex = q.options.indexOf(opt);
                                                      });
                                                    },
                                                    child: Container(
                                                      margin: const EdgeInsets.only(bottom: 8),
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                      decoration: BoxDecoration(
                                                        color: isCorrect
                                                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                                            : isSelected
                                                                ? const Color(0xFF2563EB).withValues(alpha: 0.3)
                                                                : const Color(0xFF1E202B),
                                                        borderRadius: BorderRadius.circular(10),
                                                        border: Border.all(
                                                          color: isCorrect
                                                              ? const Color(0xFF10B981)
                                                              : isSelected
                                                                  ? const Color(0xFF38BDF8)
                                                                  : Colors.white.withValues(alpha: 0.08),
                                                          width: isCorrect || isSelected ? 1.5 : 1,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              opt,
                                                              style: TextStyle(
                                                                color: isCorrect ? const Color(0xFF34D399) : Colors.white70,
                                                                fontSize: 14,
                                                                fontWeight: isCorrect ? FontWeight.bold : FontWeight.normal,
                                                              ),
                                                            ),
                                                          ),
                                                          if (isCorrect)
                                                            const Icon(LucideIcons.checkCircle2, color: Color(0xFF34D399), size: 16),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }),
                                                const SizedBox(height: 8),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    TextButton.icon(
                                                      onPressed: () {
                                                        setState(() {
                                                          q.revealAnswer = !q.revealAnswer;
                                                        });
                                                      },
                                                      icon: Icon(q.revealAnswer ? LucideIcons.eyeOff : LucideIcons.eye, size: 14, color: const Color(0xFF38BDF8)),
                                                      label: Text(
                                                        q.revealAnswer ? 'Hide Answer' : 'Show Answer',
                                                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                    if (q.revealAnswer && q.correctAnswer.isNotEmpty)
                                                      Text(
                                                        q.correctAnswer,
                                                        style: const TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.bold),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      )
                                    : _buildFormattedTextView(provider.aiResultText),
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
