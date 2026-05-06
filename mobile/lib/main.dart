import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/planner_provider.dart';
import 'screens/goals_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'widgets/bottom_nav_bar.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PlannerProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AI Planner',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFE3F2FD),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE3F2FD),
            brightness: Brightness.light,
          ),
        ),
        home: const ShellScreen(),
      ),
    );
  }
}

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int currentIndex = 0;

  void _setIndex(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFE3F2FD),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: IndexedStack(
          key: ValueKey<int>(currentIndex),
          index: currentIndex,
          children: const [
            HomeScreen(),
            GoalsScreen(),
            ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: GlassBottomNavBar(
        currentIndex: currentIndex,
        onTap: _setIndex,
      ),
    );
  }
}
