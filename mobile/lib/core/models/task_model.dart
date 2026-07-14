class TaskModel {
  final int id;
  final String title;
  final String description;
  final String priority;
  final int estimatedMin;
  final String status;
  final List<String> tags;
  final String? deadline;
  final String? recordedAt;
  final String? scheduledAt;

  const TaskModel({
    required this.id,
    required this.title,
    this.description = '',
    required this.priority,
    required this.estimatedMin,
    required this.status,
    required this.tags,
    required this.deadline,
    required this.recordedAt,
    this.scheduledAt,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final tagsValue = json['tags'];
    return TaskModel(
      id: _asInt(json['id']),
      title: (json['title'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      priority: (json['priority'] ?? 'low').toString().trim().toLowerCase(),
      estimatedMin: _asInt(json['estimated_min'] ?? json['estimatedMin']),
      status: (json['status'] ?? 'pending').toString().trim().toLowerCase(),
      tags: tagsValue is List
          ? tagsValue
              .map((item) => item.toString().trim())
              .where((tag) => tag.isNotEmpty)
              .toList()
          : <String>[],
      deadline: _asNullableString(json['deadline'] ?? json['date']),
      recordedAt: _asNullableString(json['recorded_at'] ?? json['recordedAt']),
      scheduledAt:
          _asNullableString(json['scheduled_at'] ?? json['scheduledAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'priority': priority,
      'estimated_min': estimatedMin,
      'status': status,
      'tags': tags,
      'deadline': deadline,
      'recorded_at': recordedAt,
      'scheduled_at': scheduledAt,
    };
  }

  TaskModel copyWith({
    int? id,
    String? title,
    String? description,
    String? priority,
    int? estimatedMin,
    String? status,
    List<String>? tags,
    String? deadline,
    String? recordedAt,
    String? scheduledAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      estimatedMin: estimatedMin ?? this.estimatedMin,
      status: status ?? this.status,
      tags: tags ?? this.tags,
      deadline: deadline ?? this.deadline,
      recordedAt: recordedAt ?? this.recordedAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _asNullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
