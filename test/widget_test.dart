import 'package:flutter_test/flutter_test.dart';
import 'package:pencilai_whitebaord_app/features/whiteboard/state/whiteboard_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WhiteboardProvider initializes with default pen tool and canvas settings', () {
    final provider = WhiteboardProvider();
    expect(provider.currentTool, equals(WhiteboardTool.pen));
    expect(provider.isAutoNibDetectionEnabled, isTrue);
    expect(WhiteboardProvider.themeBackgroundColors.length, equals(24));
  });
}
