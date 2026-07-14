import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RecordButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onPressed;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.onPressed,
  });

  //  UI-CUSTOMIZATION: Меняй цвета/отступы ниже
  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = isRecording ? AppColors.error : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor,
            boxShadow: [
              BoxShadow(
                color: backgroundColor.withOpacity(0.28),
                blurRadius: isRecording ? 24 : 16,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            size: 42,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
