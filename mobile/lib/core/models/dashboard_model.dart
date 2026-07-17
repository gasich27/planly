import 'task_model.dart';

class DashboardTaskModel {
  final int planId;
  final TaskModel task;

  const DashboardTaskModel({
    required this.planId,
    required this.task,
  });

  factory DashboardTaskModel.fromJson(Map<String, dynamic> json) {
    return DashboardTaskModel(
      planId: _asInt(json['plan_id']),
      task: TaskModel.fromJson(json),
    );
  }
}

class DashboardModel {
  final String context;
  final DateTime date;
  final DateTime rangeEnd;
  final int percentage;
  final int completed;
  final int total;
  final List<DashboardTaskModel> priorityTasks;
  final String summary;
  final String focusStart;
  final String focusEnd;
  final int mainTasks;
  final int breakMinutes;
  final String personalTip;

  const DashboardModel({
    required this.context,
    required this.date,
    required this.rangeEnd,
    required this.percentage,
    required this.completed,
    required this.total,
    required this.priorityTasks,
    required this.summary,
    required this.focusStart,
    required this.focusEnd,
    required this.mainTasks,
    required this.breakMinutes,
    required this.personalTip,
  });

  factory DashboardModel.fromJson(Map<String, dynamic> json) {
    final tasks = json['priority_tasks'];
    return DashboardModel(
      context: (json['context'] ?? 'today').toString(),
      date: DateTime.tryParse((json['date'] ?? '').toString()) ?? DateTime.now(),
      rangeEnd: DateTime.tryParse((json['range_end'] ?? '').toString()) ?? DateTime.now(),
      percentage: _asInt(json['percentage']).clamp(0, 100).toInt(),
      completed: _asInt(json['completed']),
      total: _asInt(json['total']),
      priorityTasks: tasks is List
          ? tasks
              .whereType<Map<String, dynamic>>()
              .map(DashboardTaskModel.fromJson)
              .toList()
          : <DashboardTaskModel>[],
      summary: (json['summary'] ?? '').toString(),
      focusStart: (json['focus_start'] ?? '09:00').toString(),
      focusEnd: (json['focus_end'] ?? '12:00').toString(),
      mainTasks: _asInt(json['main_tasks']),
      breakMinutes: _asInt(json['break_minutes']),
      personalTip: (json['personal_tip'] ?? '').toString(),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
