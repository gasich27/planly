import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFE3F2FD),
      body: SafeArea(
        child: Center(
          child: Text(
            'Goals Screen',
            style: AppTypography.headlineLarge.copyWith(color: Colors.black),
          ),
        ),
      ),
    );
  }
}
