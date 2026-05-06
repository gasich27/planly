import 'package:flutter/material.dart';

import '../core/models/task_model.dart';
import '../theme/app_theme.dart';

class TaskCard extends StatelessWidget {
  final TaskModel task;
  final ValueChanged<String>? onStatusChanged;
  final VoidCallback? onTap;

  const TaskCard({
    super.key,
    required this.task,
    this.onStatusChanged,
    this.onTap,
  });

  //  UI-CUSTOMIZATION: Меняй цвета/отступы ниже
  @override
  Widget build(BuildContext context) {
    final isDone = task.status == 'done';
    final statusColor = isDone ? AppColors.success : AppColors.warning;

    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: isDone,
                activeColor: AppColors.success,
                onChanged: (value) {
                  if (onStatusChanged != null) {
                    onStatusChanged!(value == true ? 'done' : 'pending');
                  }
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: TextStyle(
                              fontFamily: AppTypography.family,
                              fontSize: 16,
                              fontWeight: FontWeight.w300,
                              letterSpacing: -0.96,
                              color: isDone ? AppColors.textSecondary : AppColors.textPrimary,
                              decoration:
                                  isDone ? TextDecoration.lineThrough : TextDecoration.none,
                            ),
                          ),
                        ),
                        _StatusChip(
                          label: task.status,
                          color: statusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MetaChip(
                          label: task.priority,
                          color: AppColors.primary,
                        ),
                        _MetaChip(
                          label: '${task.estimatedMin} min',
                          color: AppColors.textSecondary,
                        ),
                        for (final tag in task.tags)
                          _MetaChip(
                            label: tag,
                            color: AppColors.textSecondary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.family,
          fontSize: 12,
          fontWeight: FontWeight.w300,
          letterSpacing: -0.72,
          color: color,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MetaChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.family,
          fontSize: 12,
          fontWeight: FontWeight.w300,
          letterSpacing: -0.72,
          color: color,
        ),
      ),
    );
  }
}
