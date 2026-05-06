import 'dart:ui';
import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/plan_model.dart';
import '../core/models/task_model.dart';
import '../providers/planner_provider.dart';
import '../theme/app_theme.dart';

final Uint8List _leftCircleBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAACXBIWXMAAAsTAAALEwEAmpwYAAABaWlDQ1BEaXNwbGF5IFAzAAB4nHWQvUvDUBTFT6tS0DqIDh0cMolD1NIKdnFoKxRFMFQFq1OafgltfCQpUnETVyn4H1jBWXCwiFRwcXAQRAcR3Zw6KbhoeN6XVNoi3sfl/Ticc7lcwBtQGSv2AijplpFMxKS11Lrke4OHnlOqZrKooiwK/v276/PR9d5PiFlNu3YQ2U9cl84ul3aeAlN//V3Vn8maGv3f1EGNGRbgkYmVbYsJ3iUeMWgp4qrgvMvHgtMunzuelWSc+JZY0gpqhrhJLKc79HwHl4plrbWD2N6f1VeXxRzqUcxhEyYYilBRgQQF4X/8044/ji1yV2BQLo8CLMpESRETssTz0KFhEjJxCEHqkLhz634PrfvJbW3vFZhtcM4v2tpCAzidoZPV29p4BBgaAG7qTDVUR+qh9uZywPsJMJgChu8os2HmwiF3e38M6Hvh/GMM8B0CdpXzryPO7RqFn4Er/QcXKWq8MSlPPgAAAA50RVh0U29mdHdhcmUARmlnbWGesZZjAAAAu0lEQVR4AY2RPQ7CMAyF3R8WBoTEAAtDkej978AF4ALtECRgyIIQXRDCpol4WE7UJ31W6/o5rlPQdK2YNbNlXDGhWGiYGeSH2iiW3A5MlnwNxZswRqoY1cXuezVKTneh5NBmTCfmoHK9BDEemSFhcjRuEuUlVMwjdqHf/0VTG0DTt1Zfx5xZMFfDhA1JX8cz0Bgm0SU+lGTrxrxU7oy5lFFO7VTO4UvKKOrhBNm6x49VxvimcePLMOaf8QNJUigbXKopAAAAAABJRU5ErkJggg==',
);

final Uint8List _rightCircleBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAwAAAASCAYAAABvqT8MAAAACXBIWXMAAAsTAAALEwEAmpwYAAABaWlDQ1BEaXNwbGF5IFAzAAB4nHWQvUvDUBTFT6tS0DqIDh0cMolD1NIKdnFoKxRFMFQFq1OafgltfCQpUnETVyn4H1jBWXCwiFRwcXAQRAcR3Zw6KbhoeN6XVNoi3sfl/Ticc7lcwBtQGSv2AijplpFMxKS11Lrke4OHnlOqZrKooiwK/v276/PR9d5PiFlNu3YQ2U9cl84ul3aeAlN//V3Vn8maGv3f1EGNGRbgkYmVbYsJ3iUeMWgp4qrgvMvHgtMunzuelWSc+JZY0gpqhrhJLKc79HwHl4plrbWD2N6f1VeXxRzqUcxhEyYYilBRgQQF4X/8044/ji1yV2BQLo8CLMpESRETssTz0KFhEjJxCEHqkLhz634PrfvJbW3vFZhtcM4v2tpCAzidoZPV29p4BBgaAG7qTDVUR+qh9uZywPsJMJgChu8os2HmwiF3e38M6Hvh/GMM8B0CdpXzryPO7RqFn4Er/QcXKWq8MSlPPgAAAA50RVh0U29mdHdhcmUARmlnbWGesZZjAAAAz0lEQVR4Ac2SPwvCMBDFE2uEFtFB0A6CICiIm5urX97VURQU0bWgFRTUwXfkCSFpdRJ68CNc8l7+3WkVxhCMwBOcwMZdjDxxB8w4b5hn4P4R1DxDqsLouYlvMAWGxjfDz6igoQ7Gyn7bsUTz4NgHiRikUDca8gLDlaPoYrnSBbR4mm/KORdTk0tFtbIFayrbCgcKZVzTOAVtsI24KC3Q5U6Sn/kuOXUCBsxXmjskYE6DREaxzBuKl/JW7dzX8MdSx/gCO7BXtntLY0GC+H+l39ocJsTs5egZAAAAAElFTkSuQmCC',
);

double _tracking(double fontSize) => -fontSize * 0.06;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3F2FD),
      body: const Stack(
        fit: StackFit.expand,
        children: [
          ImageAssetBackground(),
          _HomeBody(),
        ],
      ),
    );
  }
}

class ImageAssetBackground extends StatelessWidget {
  const ImageAssetBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/backgrounds/image2.png',
      fit: BoxFit.cover,
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bannerWidth = constraints.maxWidth - 32;
        final scale = bannerWidth / 361.0;
        final tripleBannerHeight = 430.0 * scale * 0.9;
        final tripleBottomPadding = 60 * scale;
        final thirdBarOffset = 58.0 * scale;
        final dateHeaderHeight = 40.0 * scale;
        final dateGap = 12.0 * scale;
        final thirdBarTop = constraints.maxHeight -
            tripleBottomPadding -
            tripleBannerHeight +
            thirdBarOffset;
        final dateTop = math.max(0.0, thirdBarTop - dateHeaderHeight - dateGap);

        return SafeArea(
          child: Consumer<PlannerProvider>(
            builder: (context, provider, child) {
              final items = _topTasks(provider.plans);
              final displayItems = _buildDisplayItems(items);

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: dateTop,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _DateHeader(
                        width: bannerWidth * 0.7,
                        scale: scale,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 60 * scale),
                      child: _TripleBanner(
                        width: bannerWidth,
                        scale: scale,
                        items: displayItems,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 40 * scale),
                      child: _ActionBanner(
                        width: bannerWidth,
                        scale: scale,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<_BannerTaskItem> _buildDisplayItems(List<_TaskFeedItem> tasks) {
    if (tasks.isEmpty) {
      return List<_BannerTaskItem>.filled(3, const _BannerTaskItem.empty(), growable: false);
    }

    final items = <_BannerTaskItem>[];
    for (final task in tasks.take(3)) {
      items.add(
        _BannerTaskItem(
          title: _truncateWithEllipsis(task.task.title, 40),
          subtitle: _formatSubtitle(task),
        ),
      );
    }

    while (items.length < 3) {
      items.add(const _BannerTaskItem.empty());
    }

    return items;
  }

  String _truncateWithEllipsis(String value, int maxLength) {
    final text = value.trim();
    if (text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength - 1).trimRight()}…';
  }

  List<_TaskFeedItem> _topTasks(List<PlanModel> plans) {
    final result = <_TaskFeedItem>[];

    for (final plan in plans) {
      for (final task in plan.structuredPlan) {
        if (task.status != 'done') {
          result.add(
            _TaskFeedItem(
              plan: plan,
              task: task,
              deadline: _deadlineFor(task, plan),
              recordedAt: _recordedAtFor(task, plan),
            ),
          );
        }
      }
    }

    result.sort((a, b) {
      final deadlineCompare = a.deadline.compareTo(b.deadline);
      if (deadlineCompare != 0) {
        return deadlineCompare;
      }

      final priorityCompare = _priorityRank(a.task.priority).compareTo(_priorityRank(b.task.priority));
      if (priorityCompare != 0) {
        return priorityCompare;
      }

      final recordedCompare = a.recordedAt.compareTo(b.recordedAt);
      if (recordedCompare != 0) {
        return recordedCompare;
      }

      return a.task.id.compareTo(b.task.id);
    });

    return result;
  }

  int _priorityRank(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return 0;
      case 'medium':
        return 1;
      case 'low':
        return 2;
      default:
        return 3;
    }
  }

  DateTime _deadlineFor(TaskModel task, PlanModel plan) {
    final raw = task.deadline?.trim();
    if (raw != null && raw.isNotEmpty) {
      final parsed = _parseDateTime(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    final recorded = plan.recordedAt?.toLocal() ?? plan.createdAt.toLocal();
    return recorded.add(const Duration(days: 3));
  }

  DateTime _recordedAtFor(TaskModel task, PlanModel plan) {
    final raw = task.recordedAt?.trim();
    if (raw != null && raw.isNotEmpty) {
      final parsed = _parseDateTime(raw);
      if (parsed != null) {
        return parsed;
      }
    }
    return plan.recordedAt?.toLocal() ?? plan.createdAt.toLocal();
  }

  DateTime? _parseDateTime(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed.toLocal();
    }

    final withZone = raw.endsWith('Z') ? raw : '${raw}Z';
    final parsedWithZone = DateTime.tryParse(withZone);
    if (parsedWithZone != null) {
      return parsedWithZone.toLocal();
    }

    final dateOnly = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final parsedDateOnly = DateTime.tryParse('${dateOnly}T00:00:00Z');
    return parsedDateOnly?.toLocal();
  }

  String _formatSubtitle(_TaskFeedItem item) {
    final deadlineText = _formatDate(item.deadline);
    final priorityText = item.task.priority;
    final tagsText = item.task.tags.isEmpty ? '' : item.task.tags.join(', ');
    final parts = <String>[deadlineText, priorityText];
    if (tagsText.isNotEmpty) {
      parts.add(tagsText);
    }
    return parts.join(' • ');
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day.$month';
  }

}

class _TaskFeedItem {
  final PlanModel plan;
  final TaskModel task;
  final DateTime deadline;
  final DateTime recordedAt;

  const _TaskFeedItem({
    required this.plan,
    required this.task,
    required this.deadline,
    required this.recordedAt,
  });
}

class _DateHeader extends StatelessWidget {
  final double width;
  final double scale;

  const _DateHeader({
    required this.width,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _dayNumber(yesterday),
            style: TextStyle(
              color: Colors.black.withOpacity(0.85),
              fontSize: 18 * scale,
              fontFamily: AppTypography.family,
              fontWeight: FontWeight.w300,
              letterSpacing: _tracking(18 * scale),
            ),
          ),
          SizedBox(width: width * 0.035),
          Container(
            width: width * 0.09,
            height: 1,
            color: Colors.black.withOpacity(0.5),
          ),
          Expanded(
            child: Center(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: _monthDay(today),
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 27 * scale,
                        fontFamily: AppTypography.family,
                        fontWeight: FontWeight.w300,
                        letterSpacing: _tracking(27 * scale),
                      ),
                    ),
                    TextSpan(
                      text: _daySuffix(today.day),
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 18 * scale,
                        fontFamily: AppTypography.family,
                        fontWeight: FontWeight.w300,
                        letterSpacing: _tracking(18 * scale),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: width * 0.09,
            height: 1,
            color: Colors.black.withOpacity(0.5),
          ),
          SizedBox(width: width * 0.035),
          Text(
            _dayNumber(tomorrow),
            style: TextStyle(
              color: Colors.black.withOpacity(0.85),
              fontSize: 18 * scale,
              fontFamily: AppTypography.family,
              fontWeight: FontWeight.w300,
              letterSpacing: _tracking(18 * scale),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBanner extends StatelessWidget {
  final double width;
  final double scale;

  const _ActionBanner({
    required this.width,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final bannerHeight = 67.0 * scale * 1;
    final circleSize = 56.0 * scale * 1;
    final circleInset = (bannerHeight - circleSize) / 2;
    final radius = 31.0 * scale * 1;

    return SizedBox(
      width: width,
      height: bannerHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: width,
            height: bannerHeight,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.34),
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: circleInset,
                  top: circleInset,
                  child: _MiniCircle(
                    size: circleSize,
                    background: const Color(0xFFFF7F48).withOpacity(0.14),
                    useGradient: true,
                  ),
                ),
                Positioned(
                  left: circleSize + circleInset + 18,
                  right: circleSize + circleInset + 18,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Add, edit, execute . . .',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black.withOpacity(0.4),
                        fontSize: 13 * scale,
                        fontFamily: AppTypography.family,
                        fontWeight: FontWeight.w300,
                        letterSpacing: _tracking(13 * scale),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: circleInset,
                  top: circleInset,
                  child: _TrailingCircle(
                    size: circleSize,
                    icon: Icons.send_rounded,
                  ),
                ),
                Positioned(
                  left: circleInset + circleSize * 0.34,
                  top: circleInset + circleSize * 0.34,
                  child: Icon(
                    Icons.mic_rounded,
                    size: circleSize * 0.34,
                    color: Colors.black.withOpacity(0.385),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _dayNumber(DateTime value) {
  return value.day.toString();
}

String _monthDay(DateTime value) {
  const months = <int, String>{
    1: 'January',
    2: 'February',
    3: 'March',
    4: 'April',
    5: 'May',
    6: 'June',
    7: 'July',
    8: 'August',
    9: 'September',
    10: 'October',
    11: 'November',
    12: 'December',
  };
  return '${months[value.month] ?? ''} ${value.day}';
}

String _daySuffix(int day) {
  if (day % 100 >= 11 && day % 100 <= 13) {
    return 'th';
  }
  switch (day % 10) {
    case 1:
      return 'st';
    case 2:
      return 'nd';
    case 3:
      return 'rd';
    default:
      return 'th';
  }
}

class _BannerCircle extends StatelessWidget {
  final double size;
  final Color background;
  final bool useGradient;
  final Uint8List imageBytes;
  final double imageScale;

  const _BannerCircle({
    required this.size,
    required this.background,
    required this.useGradient,
    required this.imageBytes,
    required this.imageScale,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: useGradient
              ? const RadialGradient(
                  center: Alignment.center,
                  radius: 0.85,
                  colors: [
                    Color(0xFFFF7F48),
                    Color(0xFFFFA800),
                  ],
                )
              : null,
          color: useGradient ? null : background,
        ),
        child: Center(
          child: Image.memory(
            imageBytes,
            width: size * imageScale,
            height: size * imageScale,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

class _TripleBanner extends StatelessWidget {
  final double width;
  final double scale;
  final List<_BannerTaskItem> items;

  const _TripleBanner({
    required this.width,
    required this.scale,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final bannerWidth = width;
    final bannerHeight = 181.0 * scale * 0.9;
    final barHeight = 58.0 * scale * 0.9;
    final barRadius = 29.0 * scale * 0.9;
    final circleSize = 47.0 * scale * 0.9;
    final circleInset = (barHeight - circleSize) / 2;
    final verticalStep = 58.0 * scale;
    final topY = -verticalStep;
    final middleY = 0.0;
    final bottomY = verticalStep;

    return SizedBox(
      width: bannerWidth,
      height: bannerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _TripleRowBar(
            width: bannerWidth,
            height: barHeight,
            radius: barRadius,
            color: Colors.white.withOpacity(0.66),
            y: topY,
            circleSize: circleSize,
            circleInset: circleInset,
            item: items[0],
          ),
          _TripleRowBar(
            width: bannerWidth,
            height: barHeight,
            radius: barRadius,
            color: Colors.white.withOpacity(0.66),
            y: middleY,
            circleSize: circleSize,
            circleInset: circleInset,
            item: items[1],
          ),
          _TripleRowBar(
            width: bannerWidth,
            height: barHeight,
            radius: barRadius,
            color: Colors.white.withOpacity(0.66),
            y: bottomY,
            circleSize: circleSize,
            circleInset: circleInset,
            item: items[2],
          ),
          Positioned(
            left: circleInset,
            top: topY + circleInset,
            child: _MiniCircle(
              size: circleSize,
              useGradient: true,
              background: const Color(0xFFFF7F48).withOpacity(0.14),
            ),
          ),
          Positioned(
            left: circleInset,
            top: middleY + circleInset,
            child: _MiniCircle(
              size: circleSize,
              useGradient: true,
              background: const Color(0xFFFF7F48).withOpacity(0.14),
            ),
          ),
          Positioned(
            left: circleInset,
            top: bottomY + circleInset,
            child: _MiniCircle(
              size: circleSize,
              useGradient: true,
              background: const Color(0xFFFF7F48).withOpacity(0.14),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripleRowBar extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final Color color;
  final double y;
  final double circleSize;
  final double circleInset;
  final _BannerTaskItem item;

  const _TripleRowBar({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
    required this.y,
    required this.circleSize,
    required this.circleInset,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: y,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.34),
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: circleSize + circleInset + (radius * 0.8),
                      right: circleSize + circleInset + (radius * 0.8),
                    ),
                    child: _TaskTextBlock(item: item),
                  ),
                ),
                Positioned(
                  right: circleInset,
                  top: circleInset,
                  child: _TrailingCircle(
                    size: circleSize,
                    icon: Icons.edit_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskTextBlock extends StatelessWidget {
  final _BannerTaskItem item;

  const _TaskTextBlock({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    if (item.title.isEmpty && item.subtitle.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final titleSize = constraints.maxWidth < 170 ? 11.0 : 12.0;
        final subtitleSize = constraints.maxWidth < 170 ? 8.0 : 9.0;

        return Align(
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                maxLines: 1,
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: titleSize,
                    fontFamily: AppTypography.family,
                    fontWeight: FontWeight.w400,
                    letterSpacing: _tracking(titleSize),
                    height: 1.0,
                  ),
                ),
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  textAlign: TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.4),
                    fontSize: subtitleSize,
                    fontFamily: AppTypography.family,
                    fontWeight: FontWeight.w400,
                    letterSpacing: _tracking(subtitleSize),
                    height: 1.0,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BannerTaskItem {
  final String title;
  final String subtitle;

  const _BannerTaskItem({
    required this.title,
    required this.subtitle,
  });

  const _BannerTaskItem.empty()
      : title = '',
        subtitle = '';
}

class _TrailingCircle extends StatelessWidget {
  final double size;
  final IconData icon;

  const _TrailingCircle({
    required this.size,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF5D7B8).withOpacity(0.40),
      ),
      child: Center(
        child: Transform.rotate(
          angle: icon == Icons.send_rounded ? -0.78539816339 : 0,
          child: Icon(
            icon,
            size: size * 0.38,
            color: Colors.black.withOpacity(0.385),
          ),
        ),
      ),
    );
  }
}

class _MiniCircle extends StatelessWidget {
  final double size;
  final Color background;
  final bool useGradient;

  const _MiniCircle({
    required this.size,
    required this.background,
    required this.useGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: useGradient
            ? const RadialGradient(
                center: Alignment.center,
                radius: 0.85,
                colors: [
                  Color(0xFFFF7F48),
                  Color(0xFFFFA800),
                ],
              )
            : null,
        color: useGradient ? null : background,
      ),
    );
  }
}
