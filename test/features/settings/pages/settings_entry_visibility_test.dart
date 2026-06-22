import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/desktop/setting/about_pane.dart';
import 'package:Kelivo/features/settings/pages/about_page.dart';
import 'package:Kelivo/features/settings/pages/settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildApp(Widget child, {List<SingleChildWidget> providers = const []}) {
  final app = MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  if (providers.isEmpty) {
    return app;
  }

  return MultiProvider(providers: providers, child: app);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('设置页不再显示 Docs 和 Sponsor 入口', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        const SettingsPage(),
        providers: [
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Docs'), findsNothing);
    expect(find.text('Sponsor'), findsNothing);
  });

  testWidgets('移动端关于页显示 QQ 群入口', (tester) async {
    await tester.pumpWidget(
      _buildApp(
        const AboutPage(),
        providers: [
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Join our QQ Group'), findsOneWidget);
  });

  testWidgets('桌面关于页显示 QQ 群和 Sponsor 入口', (tester) async {
    await tester.pumpWidget(_buildApp(const DesktopAboutPane()));
    await tester.pumpAndSettle();

    expect(find.text('Join our QQ Group'), findsOneWidget);
    expect(find.text('Sponsor'), findsOneWidget);
  });
}
