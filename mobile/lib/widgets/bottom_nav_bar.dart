import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GlassBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 45),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.66),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.09),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth / 3;
                  const activeInset = 3.5;
                  final activeLeft = itemWidth * currentIndex;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedPositioned(
                        left: activeLeft,
                        top: 0,
                        width: itemWidth,
                        height: 44,
                        duration: const Duration(milliseconds: 980),
                        curve: Curves.easeInOutSine,
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: activeInset),
                            width: itemWidth - (activeInset * 2),
                            height: 44 - (activeInset * 2),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 255, 201, 120).withOpacity(0.62),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _NavItem(
                              label: 'Today',
                              isActive: currentIndex == 0,
                              onTap: () => onTap(0),
                            ),
                          ),
                          Expanded(
                            child: _NavItem(
                              label: 'Goals',
                              isActive: currentIndex == 1,
                              onTap: () => onTap(1),
                            ),
                          ),
                          Expanded(
                            child: _NavItem(
                              label: 'Profile',
                              isActive: currentIndex == 2,
                              onTap: () => onTap(2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.family,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: isActive ? Colors.black : Colors.black87,
                  letterSpacing: -0.66,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
