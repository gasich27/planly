import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui show TextDirection;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../core/models/dashboard_model.dart';
import '../core/models/story_branch_model.dart';
import '../providers/planner_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/planning_stories.dart';

const _orange = Color(0xFFFF8300);
const _glassBorder = Color(0xB8FFFFFF);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _commandController = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  late final AnimationController _waveController;
  final String _activeContext = 'today';
  String? _audioPath;
  bool _isRecording = false;
  PlanningStoryBranch? _selectedStoryBranch;

  String get _backendContext =>
      _activeContext.startsWith('plan:') ? 'today' : _activeContext;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    _commandController.dispose();
    _commandFocus.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _openPlanCommandEditor({required bool isEdit}) async {
    final provider = context.read<PlannerProvider>();
    final branches = <PlanningStoryBranch>[
      ...PlanningStoryBranch.defaults(DateTime.now()),
      ...provider.storyBranches.map(PlanningStoryBranch.custom),
    ];
    final result = await showPlanCommandEditor(
      context,
      isEdit: isEdit,
      branches: branches,
      selectedBranch: _selectedStoryBranch,
      transcribeAudio: provider.transcribeAudio,
    );
    if (result == null || !mounted) {
      return;
    }
    final rangeText =
        '${DateFormat('yyyy-MM-dd').format(result.dateRange.start)} to '
        '${DateFormat('yyyy-MM-dd').format(result.dateRange.end)}';
    final command = '''${result.command}
Story branch: ${result.branchTitle} (${result.branchId})
Date range: $rangeText
Story grouping: ${result.grouping}
Placement: ${result.placement} the selected date range.''';
    if (isEdit && provider.plans.isNotEmpty) {
      await provider.aiEditPlan(provider.plans.first.id, command);
    } else {
      await provider.createPlanFromText(command, period: result.period);
    }
  }

  Future<void> _createStoryBranch() async {
    final branch = await showPlanlyStoryBranchEditor(context);
    if (branch == null || !mounted) {
      return;
    }
    await context.read<PlannerProvider>().saveStoryBranch(branch);
  }

  Future<void> _editCurrentStoryBranch() async {
    final selected = _selectedStoryBranch;
    if (selected == null || !selected.isCustom) {
      await _openPlanCommandEditor(isEdit: true);
      return;
    }
    final provider = context.read<PlannerProvider>();
    StoryBranchModel? initial;
    for (final branch in provider.storyBranches) {
      if (branch.id == selected.id) {
        initial = branch;
        break;
      }
    }
    if (initial == null) {
      return;
    }
    final updated =
        await showPlanlyStoryBranchEditor(context, initial: initial);
    if (updated == null || !mounted) {
      return;
    }
    await provider.saveStoryBranch(updated);
    setState(() => _selectedStoryBranch = PlanningStoryBranch.custom(updated));
  }

  Future<void> _openStoryBranch(PlanningStoryBranch branch) async {
    setState(() => _selectedStoryBranch = branch);
    final plans = context.read<PlannerProvider>().plans;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 480),
        reverseTransitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (context, animation, secondaryAnimation) =>
            PlanningStoryViewerScreen(branch: branch, plans: plans),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      _waveController.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = false;
        _audioPath = path;
      });
      return;
    }

    if (kIsWeb) {
      _showMessage('Voice recording is available in the iOS and Android app.');
      return;
    }
    if (!await _recorder.hasPermission()) {
      _showMessage('Microphone permission is required.');
      return;
    }
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/planly_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isRecording = true;
      _audioPath = null;
    });
    _waveController.repeat();
  }

  Future<void> _sendCommand() async {
    final provider = context.read<PlannerProvider>();
    try {
      if (_isRecording) {
        await _toggleRecording();
      }
      final text = _commandController.text.trim();
      if (text.isNotEmpty) {
        await provider.createPlanFromText(text, period: _backendContext);
        _commandController.clear();
      } else if (_audioPath != null) {
        await provider.createPlanFromAudio(File(_audioPath!));
        _audioPath = null;
      } else {
        _showMessage('Type a command or record your voice.');
        return;
      }
      if (mounted) {
        await provider.loadDashboard(_backendContext);
      }
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _Background(),
          SafeArea(
            bottom: false,
            child: Consumer<PlannerProvider>(
              builder: (context, provider, child) {
                final dashboard = provider.dashboard;
                final screenHeight = MediaQuery.sizeOf(context).height;
                final lowerSectionTop =
                    (screenHeight * 0.058).clamp(44.0, 54.0);
                final lowerSectionBottom = 152.0 - lowerSectionTop;
                return RefreshIndicator(
                  color: _orange,
                  onRefresh: provider.loadPlans,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.only(top: 18),
                        sliver: SliverToBoxAdapter(
                          child: PlanningStoriesStrip(
                            customBranches: provider.storyBranches,
                            onAddPlan: () =>
                                _openPlanCommandEditor(isEdit: false),
                            onEditPlan: _editCurrentStoryBranch,
                            onCreateBranch: _createStoryBranch,
                            onOpenBranch: _openStoryBranch,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(28, 30, 28, 0),
                        sliver: SliverToBoxAdapter(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 620),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _ProgressSection(
                              key: ValueKey(
                                  '${dashboard?.context}-${dashboard?.percentage}'),
                              dashboard: dashboard,
                              contextName: _activeContext,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding:
                            EdgeInsets.fromLTRB(28, lowerSectionTop, 28, 0),
                        sliver: SliverToBoxAdapter(
                          child: _DateSelector(
                              date: dashboard?.date ?? DateTime.now()),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(28, 22, 28, 0),
                        sliver: SliverToBoxAdapter(
                          child: _PriorityTasks(
                            dashboard: dashboard,
                            isLoading: provider.isLoading,
                            onToggle: (item) async {
                              final status = item.task.status == 'done'
                                  ? 'pending'
                                  : 'done';
                              await provider.toggleTaskStatus(
                                item.planId,
                                item.task.id,
                                status,
                              );
                            },
                            onAiEdit: (item) => _editTask(item),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          28,
                          6,
                          28,
                          lowerSectionBottom,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _VoiceCommandBar(
                            controller: _commandController,
                            focusNode: _commandFocus,
                            waveController: _waveController,
                            isRecording: _isRecording,
                            hasAudio: _audioPath != null,
                            isLoading: provider.isLoading,
                            onMicTap: _toggleRecording,
                            onSend: _sendCommand,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTask(DashboardTaskModel item) async {
    final controller = TextEditingController();
    final instruction = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.94),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text('Edit with AI'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Move it to tomorrow, shorten it…',
            filled: true,
            fillColor: const Color(0xFFFFF2DF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (instruction == null || instruction.isEmpty || !mounted) {
      return;
    }
    await context.read<PlannerProvider>().aiEditPlan(
          item.planId,
          'For the task "${item.task.title}": $instruction',
        );
  }
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Image.asset(
        'assets/backgrounds/image2.png',
        fit: BoxFit.cover,
        alignment: Alignment.center,
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  final DashboardModel? dashboard;
  final String contextName;

  const _ProgressSection(
      {super.key, required this.dashboard, required this.contextName});

  @override
  Widget build(BuildContext context) {
    final percentage = dashboard?.percentage ?? 0;
    final label = switch (contextName) {
      'tomorrow' => 'Tomorrow',
      'week' => 'Week',
      'month' => 'Month',
      _ => 'Today',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final percentSize = math.min(126.0, math.max(96.0, width * 0.33));
        const labelTop = 7.0;
        const labelSize = 22.0;
        const labelHeight = 27.0;
        const verticalGap = 16.0;
        final percentTop = labelTop + labelHeight + verticalGap;
        final percentLineHeight = percentSize * 0.92;
        final percentVisibleHeight = percentSize * 0.68;
        final subtitleTop = percentTop + percentVisibleHeight + verticalGap;
        final sectionHeight = subtitleTop + 28;
        return SizedBox(
          height: sectionHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ProgressPathPainter(
                    label: label,
                    percentage: percentage,
                    labelSize: labelSize,
                    percentSize: percentSize,
                    startY: labelTop + labelHeight / 2,
                    arrowY: percentTop + percentLineHeight / 2,
                  ),
                ),
              ),
              Positioned(
                left: 2,
                top: labelTop,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTypography.family,
                    fontSize: labelSize,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -1.4,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: percentTop,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: percentage.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Text(
                    '${value.round()}%',
                    style: TextStyle(
                      fontFamily: AppTypography.family,
                      fontSize: percentSize,
                      height: 0.92,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -percentSize * 0.06,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 2,
                top: subtitleTop,
                child: Text(
                  'of the plan was completed ${label.toLowerCase()}',
                  style: TextStyle(
                    fontFamily: AppTypography.family,
                    fontSize: math.min(18, width * 0.047),
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressPathPainter extends CustomPainter {
  final String label;
  final int percentage;
  final double labelSize;
  final double percentSize;
  final double startY;
  final double arrowY;

  const _ProgressPathPainter({
    required this.label,
    required this.percentage,
    required this.labelSize,
    required this.percentSize,
    required this.startY,
    required this.arrowY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.black.withOpacity(0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: AppTypography.family,
          fontSize: labelSize,
          fontWeight: FontWeight.w400,
          letterSpacing: -1.4,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final percentagePainter = TextPainter(
      text: TextSpan(
        text: '$percentage%',
        style: TextStyle(
          fontFamily: AppTypography.family,
          fontSize: percentSize,
          fontWeight: FontWeight.w400,
          letterSpacing: -percentSize * 0.06,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final startX = (labelPainter.width + 28)
        .clamp(
          size.width * 0.22,
          size.width * 0.46,
        )
        .toDouble();
    final arrowX = (percentagePainter.width + 28)
        .clamp(
          size.width * 0.58,
          size.width * 0.76,
        )
        .toDouble();
    final path = Path()
      ..moveTo(startX, startY)
      ..lineTo(size.width * 0.87, startY)
      ..quadraticBezierTo(
        size.width * 0.98,
        startY,
        size.width * 0.98,
        startY + (arrowY - startY) * 0.36,
      )
      ..lineTo(size.width * 0.98, startY + (arrowY - startY) * 0.64)
      ..quadraticBezierTo(
        size.width * 0.98,
        arrowY,
        size.width * 0.87,
        arrowY,
      )
      ..lineTo(arrowX, arrowY);
    final arrow = Path()
      ..moveTo(arrowX, arrowY)
      ..lineTo(arrowX + 8, arrowY - 5)
      ..moveTo(arrowX, arrowY)
      ..lineTo(arrowX + 8, arrowY + 5);
    canvas
      ..drawPath(path, line)
      ..drawPath(arrow, line);
  }

  @override
  bool shouldRepaint(covariant _ProgressPathPainter oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.percentage != percentage ||
        oldDelegate.percentSize != percentSize ||
        oldDelegate.startY != startY ||
        oldDelegate.arrowY != arrowY;
  }
}

class _DateSelector extends StatelessWidget {
  final DateTime date;

  const _DateSelector({required this.date});

  @override
  Widget build(BuildContext context) {
    final previous = date.subtract(const Duration(days: 1));
    final next = date.add(const Duration(days: 1));
    final suffix = _ordinal(date.day);
    return SizedBox(
      height: 42,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            child: Text('${previous.day}',
                textAlign: TextAlign.center, style: _dateSideStyle),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Divider(color: Colors.black87, thickness: 0.8),
          ),
          const SizedBox(width: 18),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Colors.black,
                fontFamily: AppTypography.family,
              ),
              children: [
                TextSpan(
                  text: DateFormat('MMMM d').format(date),
                  style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -1.7,
                  ),
                ),
                TextSpan(
                  text: suffix,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          const Expanded(
            child: Divider(color: Colors.black87, thickness: 0.8),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            child: Text('${next.day}',
                textAlign: TextAlign.center, style: _dateSideStyle),
          ),
        ],
      ),
    );
  }
}

class _PriorityTasks extends StatelessWidget {
  final DashboardModel? dashboard;
  final bool isLoading;
  final ValueChanged<DashboardTaskModel> onToggle;
  final ValueChanged<DashboardTaskModel> onAiEdit;

  const _PriorityTasks({
    required this.dashboard,
    required this.isLoading,
    required this.onToggle,
    required this.onAiEdit,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = (dashboard?.priorityTasks ?? <DashboardTaskModel>[])
        .take(3)
        .toList(growable: false);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 700),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      child: Column(
        key: ValueKey(
            tasks.map((item) => '${item.planId}:${item.task.id}').join(',')),
        children: [
          for (var index = 0; index < 3; index++) ...[
            if (index < tasks.length)
              _TaskCard(
                item: tasks[index],
                onToggle: () => onToggle(tasks[index]),
                onAiEdit: () => onAiEdit(tasks[index]),
              )
            else
              _EmptyPriorityTaskCard(isLoading: isLoading),
            if (index != 2) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DashboardTaskModel item;
  final VoidCallback onToggle;
  final VoidCallback onAiEdit;

  const _TaskCard(
      {required this.item, required this.onToggle, required this.onAiEdit});

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    final description =
        task.description.isNotEmpty ? task.description : task.tags.join(', ');
    final intensity = switch (task.priority) {
      'high' => 1.0,
      'medium' => 0.78,
      _ => 0.58,
    };
    return _GlassCard(
      radius: 31,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onToggle,
              child: _GlassCircle(
                size: 50,
                colors: [
                  Color.lerp(const Color(0xFFFFC16B),
                          const Color(0xFFFF5A1F), intensity)!
                      .withOpacity(0.88),
                  const Color(0xFFFF9800).withOpacity(0.76),
                ],
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: task.status == 'done'
                      ? const Icon(
                          Icons.check_rounded,
                          key: ValueKey('done'),
                          color: Colors.white,
                          size: 24,
                        )
                      : const SizedBox(key: ValueKey('pending')),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.family,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.7,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.family,
                        fontSize: 9.5,
                        color: Colors.black.withOpacity(0.46),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAiEdit,
              child: _GlassCircle(
                size: 50,
                colors: [
                  Colors.white.withOpacity(0.46),
                  const Color(0xFFF1B97C).withOpacity(0.34),
                ],
                child: Icon(
                  Icons.auto_fix_high_rounded,
                  size: 20,
                  color: Colors.black.withOpacity(0.36),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _EmptyPriorityTaskCard extends StatelessWidget {
  final bool isLoading;

  const _EmptyPriorityTaskCard({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: 31,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            const SizedBox(width: 6),
            _GlassCircle(
              size: 50,
              colors: [
                const Color(0xFFFFB067).withOpacity(0.70),
                const Color(0xFFFF9800).withOpacity(0.58),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoading
                        ? 'Selecting a priority task...'
                        : 'Your priority task will be here',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.family,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.55,
                      color: Colors.black.withOpacity(0.58),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'AI will choose it from today\'s plan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.family,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w400,
                      color: Colors.black.withOpacity(0.34),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _GlassCircle(
              size: 50,
              colors: [
                Colors.white.withOpacity(0.38),
                const Color(0xFFF1B97C).withOpacity(0.27),
              ],
              child: Icon(
                Icons.auto_fix_high_rounded,
                size: 20,
                color: Colors.black.withOpacity(0.18),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _VoiceCommandBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final AnimationController waveController;
  final bool isRecording;
  final bool hasAudio;
  final bool isLoading;
  final VoidCallback onMicTap;
  final VoidCallback onSend;

  const _VoiceCommandBar({
    required this.controller,
    required this.focusNode,
    required this.waveController,
    required this.isRecording,
    required this.hasAudio,
    required this.isLoading,
    required this.onMicTap,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: 38,
      child: SizedBox(
        height: 78,
        child: Row(
          children: [
            const SizedBox(width: 7),
            GestureDetector(
              onTap: isLoading ? null : onMicTap,
              child: _GlassCircle(
                size: 64,
                colors: [
                  const Color(0xFFFF8A43).withOpacity(0.90),
                  const Color(0xFFFFA800).withOpacity(0.80),
                ],
                glow: isRecording,
                child: Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.black.withOpacity(0.35),
                  size: 27,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: isRecording
                  ? _AudioWave(controller: waveController)
                  : TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !isLoading,
                      onSubmitted: (_) => onSend(),
                      style: const TextStyle(
                        fontFamily: AppTypography.family,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.72,
                      ),
                      decoration: InputDecoration(
                        hintText: hasAudio
                            ? 'Voice command is ready'
                            : 'Add, edit, execute…',
                        hintStyle: TextStyle(
                          fontFamily: AppTypography.family,
                          color: Colors.black.withOpacity(0.38),
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.72,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: isLoading ? null : onSend,
              child: _GlassCircle(
                size: 64,
                colors: [
                  Colors.white.withOpacity(0.48),
                  const Color(0xFFF1B97C).withOpacity(0.38),
                ],
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(21),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _orange),
                      )
                    : Transform.rotate(
                        angle: -0.65,
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.black.withOpacity(0.36),
                          size: 27,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 7),
          ],
        ),
      ),
    );
  }
}

class _AudioWave extends StatelessWidget {
  final AnimationController controller;

  const _AudioWave({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(13, (index) {
          final phase = controller.value * math.pi * 2 + index * 0.72;
          final height = 7 + (math.sin(phase).abs() * 22);
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _orange.withOpacity(0.35 + index / 30),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  final double size;
  final List<Color> colors;
  final Widget? child;
  final bool glow;

  const _GlassCircle({
    required this.size,
    required this.colors,
    this.child,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              spreadRadius: -5,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: _orange.withOpacity(glow ? 0.34 : 0.12),
              blurRadius: glow ? 22 : 14,
              spreadRadius: glow ? 1 : -5,
            ),
          ],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 26),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.34, -0.38),
                      radius: 1.08,
                      colors: colors,
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _GlassEdgePainter(radius: size / 2),
                ),
                if (child != null) Center(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;

  const _GlassCard({required this.child, required this.radius});

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 18,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFFFF8A00).withOpacity(0.13),
            blurRadius: 30,
            spreadRadius: -10,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.55),
            blurRadius: 12,
            spreadRadius: -5,
            offset: const Offset(-2, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 42, sigmaY: 48),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    gradient: LinearGradient(
                      begin: const Alignment(-0.9, -1),
                      end: const Alignment(0.9, 1),
                      stops: const [0, 0.34, 0.72, 1],
                      colors: [
                        Colors.white.withOpacity(0.28),
                        Colors.white.withOpacity(0.10),
                        const Color(0xFFFFB04A).withOpacity(0.07),
                        Colors.white.withOpacity(0.17),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GlassEdgePainter(radius: radius),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassEdgePainter extends CustomPainter {
  final double radius;

  const _GlassEdgePainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final outerRect = Offset.zero & size;
    final outerRRect = RRect.fromRectAndRadius(
      outerRect.deflate(0.7),
      Radius.circular(math.max(0, radius - 0.7)),
    );
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..shader = const LinearGradient(
        begin: Alignment(-0.9, -1),
        end: Alignment(0.95, 1),
        stops: [0, 0.28, 0.62, 1],
        colors: [
          Color(0xF2FFFFFF),
          Color(0x8CFFFFFF),
          Color(0x38FFBE73),
          Color(0xBFFFFFFF),
        ],
      ).createShader(outerRect);
    canvas.drawRRect(outerRRect, edgePaint);
  }

  @override
  bool shouldRepaint(covariant _GlassEdgePainter oldDelegate) {
    return oldDelegate.radius != radius;
  }
}

String _ordinal(int day) {
  if (day >= 11 && day <= 13) {
    return 'th';
  }
  return switch (day % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
}

const _dateSideStyle = TextStyle(
  color: Colors.black,
  fontFamily: AppTypography.family,
  fontSize: 17,
  fontWeight: FontWeight.w300,
);
