class StoryBranchModel {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final String grouping;

  const StoryBranchModel({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.grouping,
  });

  factory StoryBranchModel.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return StoryBranchModel(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      startDate:
          DateTime.tryParse((json['start_date'] ?? '').toString()) ?? now,
      endDate: DateTime.tryParse((json['end_date'] ?? '').toString()) ?? now,
      grouping: (json['grouping'] ?? 'day').toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'grouping': grouping,
      };

  StoryBranchModel copyWith({
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? grouping,
  }) {
    return StoryBranchModel(
      id: id,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      grouping: grouping ?? this.grouping,
    );
  }
}
