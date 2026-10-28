import 'package:flutter_test/flutter_test.dart';

import 'package:darling_file/main.dart';

void main() {
  testWidgets('Darling File 冒烟测试', (WidgetTester tester) async {
    await tester.pumpWidget(const DarlingFileApp());
    await tester.pump(const Duration(milliseconds: 500));

    // 侧边栏导航项存在
    expect(find.text('发送'), findsWidgets);
    expect(find.text('接收'), findsWidgets);
    expect(find.text('历史'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    // Logo
    expect(find.text('Darling File'), findsWidgets);
  });
}
