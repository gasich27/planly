import 'task_model.dart';

class PlanModel {
  final int id;
  final String title;
  final String rawText;
  final List<TaskModel> structuredPlan;
  final String notes;
  final DateTime createdAt;
  final DateTime? recordedAt;
  final String period;

  const PlanModel({
    required this.id,
    required this.title,
    required this.rawText,
    required this.structuredPlan,
    required this.notes,
    required this.createdAt,
    this.recordedAt,
    required this.period,
  });

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    final structured = json['structured_plan'] ?? json['structuredPlan'];
    final structuredMap = structured is Map<String, dynamic>
        ? structured
        : <String, dynamic>{};
    final tasksValue = structuredMap['tasks'];
    final tasks = tasksValue is List
        ? tasksValue
            .whereType<Map<String, dynamic>>()
            .map(TaskModel.fromJson)
            .toList()
        : <TaskModel>[];

    return PlanModel(
      id: _asInt(json['id']),
      title: (structuredMap['title'] ?? json['title'] ?? '').toString().trim(),
      rawText: (json['raw_text'] ?? json['rawText'] ?? '').toString().trim(),
      structuredPlan: tasks,
      notes: (structuredMap['notes'] ?? json['notes'] ?? '').toString().trim(),
      createdAt: DateTime.tryParse((json['created_at'] ?? json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      recordedAt: DateTime.tryParse((json['recorded_at'] ?? json['recordedAt'] ?? '').toString()),
      period: (json['period'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'raw_text': rawText,
      'structured_plan': <String, dynamic>{
        'title': title,
        'tasks': structuredPlan.map((task) => task.toJson()).toList(),
        'notes': notes,
      },
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'recorded_at': recordedAt?.toIso8601String(),
      'period': period,
    };
  }

  PlanModel copyWith({
    int? id,
    String? title,
    String? rawText,
    List<TaskModel>? structuredPlan,
    String? notes,
    DateTime? createdAt,
    DateTime? recordedAt,
    String? period,
  }) {
    return PlanModel(
      id: id ?? this.id,
      title: title ?? this.title,
      rawText: rawText ?? this.rawText,
      structuredPlan: structuredPlan ?? this.structuredPlan,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      recordedAt: recordedAt ?? this.recordedAt,
      period: period ?? this.period,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
