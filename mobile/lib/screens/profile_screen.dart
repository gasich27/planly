import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFE3F2FD),
      body: SafeArea(
        child: Center(
          child: Text(
            'Profile Screen',
            style: AppTypography.headlineLarge.copyWith(color: Colors.black),
          ),
        ),
      ),
    );
  }
}
