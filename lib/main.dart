import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'ui/graph_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const RelationGraphApp());
}

class RelationGraphApp extends StatefulWidget {
  const RelationGraphApp({super.key});

  @override
  State<RelationGraphApp> createState() => _RelationGraphAppState();
}

class _RelationGraphAppState extends State<RelationGraphApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkMind',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          if (!_state.settingsLoaded) {
            return const Scaffold(
              backgroundColor: AppColors.bg,
              body: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                ),
              ),
            );
          }
          return GraphScreen(state: _state);
        },
      ),
    );
  }
}
