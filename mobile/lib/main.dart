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
        title: 'PLANLY',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Steppe',
          typography: Typography.material2021(platform: TargetPlatform.iOS),
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFF8300),
            brightness: Brightness.light,
          ),
          textTheme: ThemeData.light().textTheme.apply(
                fontFamily: 'Steppe',
              ),
          primaryTextTheme: ThemeData.light().primaryTextTheme.apply(
                fontFamily: 'Steppe',
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
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _setIndex(int index) {
    if (index == currentIndex) {
      return;
    }
    setState(() {
      currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.white,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          if (index != currentIndex) {
            setState(() => currentIndex = index);
          }
        },
        children: const [
          HomeScreen(),
          GoalsScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: GlassBottomNavBar(
        currentIndex: currentIndex,
        onTap: _setIndex,
      ),
    );
  }
}
