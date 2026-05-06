import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models/plan_model.dart';
import '../core/models/task_model.dart';
import '../providers/planner_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/task_card.dart';

class PlanDetailScreen extends StatefulWidget {
  final PlanModel plan;

  const PlanDetailScreen({
    super.key,
    required this.plan,
  });

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  bool _exporting = false;

  Future<void> _toggleStatus(TaskModel task) async {
    final nextStatus = task.status == 'done' ? 'pending' : 'done';
    final provider = context.read<PlannerProvider>();
    try {
      await provider.toggleTaskStatus(widget.plan.id, task.id, nextStatus);
      if (!mounted) {
        return;
      }
      provider.updateLocalPlanTaskStatus(widget.plan.id, task.id, nextStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Задача ${task.id} обновлена')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить задачу: $e')),
      );
    }
  }

  Future<void> _exportPlan() async {
    setState(() {
      _exporting = true;
    });
    try {
      final file = await context.read<PlannerProvider>().exportPlan(widget.plan.id);
      if (!mounted) {
        return;
      }
      await Share.shareFiles([file.path], text: 'AI Planner: ${widget.plan.title}');
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Экспорт не удался: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = widget.plan.structuredPlan.where((task) => task.status == 'done').length;
    final totalCount = widget.plan.structuredPlan.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.plan.title),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            elevation: 0,
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Дата: ${_formatDate(widget.plan.createdAt)}', style: AppTypography.bodyMedium),
                  const SizedBox(height: 4),
                  Text('Период: ${widget.plan.period}', style: AppTypography.bodyMedium),
                  const SizedBox(height: 4),
                  Text('Задач: $doneCount / $totalCount', style: AppTypography.bodyMedium),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    widget.plan.notes,
                    style: AppTypography.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...widget.plan.structuredPlan.map((task) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Dismissible(
                key: ValueKey('${widget.plan.id}_${task.id}_${task.status}'),
                background: Container(
                  decoration: BoxDecoration(
                    color: task.status == 'done' ? AppColors.warning : AppColors.success,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Icon(
                    task.status == 'done' ? Icons.undo_rounded : Icons.check_rounded,
                    color: Colors.white,
                  ),
                ),
                secondaryBackground: Container(
                  decoration: BoxDecoration(
                    color: task.status == 'done' ? AppColors.warning : AppColors.success,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Icon(
                    task.status == 'done' ? Icons.undo_rounded : Icons.check_rounded,
                    color: Colors.white,
                  ),
                ),
                confirmDismiss: (_) async {
                  await _toggleStatus(task);
                  return false;
                },
                child: TaskCard(
                  task: task,
                  onStatusChanged: (_) => _toggleStatus(task),
                ),
              ),
            );
          }),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _exporting ? null : _exportPlan,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_exporting ? 'Экспортируем...' : 'Экспорт в .ics'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}
