import 'package:flutter/material.dart';
import 'pages.dart';

void main() {
  runApp(const DarlingFileApp());
}

class DarlingFileApp extends StatelessWidget {
  const DarlingFileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Darling File',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
