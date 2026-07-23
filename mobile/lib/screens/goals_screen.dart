import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../core/models/dashboard_model.dart';
import '../core/models/plan_model.dart';
import '../core/models/task_model.dart';
import '../providers/planner_provider.dart';
import '../theme/app_theme.dart';

const _orange = Color(0xFFFF7900);
const _dark = Color(0xFF29201B);

enum _VoiceState { idle, recording, processing, ready }

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen>
    with TickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _commandController = TextEditingController();
  late final AnimationController _waveController;
  Timer? _amplitudeTimer;
  DateTime _selectedDate = _dateOnly(DateTime.now());
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _calendarWindowStart =
      _dateOnly(DateTime.now()).subtract(const Duration(days: 7));
  _VoiceState _voiceState = _VoiceState.idle;
  List<double> _levels = List<double>.filled(38, 0.18);
  bool _editMonth = false;
  String? _audioPath;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlannerProvider>().loadGoalsDashboard(_selectedDate);
    });
  }

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _waveController.dispose();
    _commandController.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _selectDate(DateTime date) async {
    setState(() => _selectedDate = _dateOnly(date));
    await context.read<PlannerProvider>().loadGoalsDashboard(date);
  }

  Future<void> _changeMonth(int offset) async {
    final month = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    final day = math.min(_selectedDate.day, DateUtils.getDaysInMonth(month.year, month.month));
    setState(() {
      _visibleMonth = month;
      _selectedDate = DateTime(month.year, month.month, day);
      _calendarWindowStart =
          _selectedDate.subtract(const Duration(days: 7));
    });
    await context.read<PlannerProvider>().loadGoalsDashboard(_selectedDate);
  }

  Future<void> _toggleRecording() async {
    if (_voiceState == _VoiceState.recording) {
      _amplitudeTimer?.cancel();
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _audioPath = path;
        _voiceState = path == null ? _VoiceState.idle : _VoiceState.processing;
      });
      if (path == null) return;
      try {
        final text = await context.read<PlannerProvider>().transcribeAudio(File(path));
        if (!mounted) return;
        _commandController.text = text;
        setState(() => _voiceState = _VoiceState.ready);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) setState(() => _voiceState = _VoiceState.idle);
      } catch (error) {
        if (mounted) {
          setState(() => _voiceState = _VoiceState.idle);
          _message(error.toString());
        }
      }
      return;
    }

    if (kIsWeb) {
      _message('Voice recording is available in the iOS and Android app.');
      return;
    }
    if (!await _recorder.hasPermission()) {
      _message('Microphone permission is required.');
      return;
    }
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/planly_goals_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (!mounted) return;
    setState(() => _voiceState = _VoiceState.recording);
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 90), (_) async {
      final amplitude = await _recorder.getAmplitude();
      if (!mounted || _voiceState != _VoiceState.recording) return;
      final normalized = ((amplitude.current + 55) / 55).clamp(0.08, 1.0);
      setState(() {
        _levels = <double>[..._levels.skip(1), normalized];
      });
    });
  }

  Future<void> _sendCommand() async {
    final text = _commandController.text.trim();
    if (text.isEmpty) {
      _message('Describe what should be changed.');
      return;
    }
    final provider = context.read<PlannerProvider>();
    setState(() => _voiceState = _VoiceState.processing);
    try {
      await provider.createPlanFromText(
        text,
        period: 'day',
        targetDate: _selectedDate,
      );
      _commandController.clear();
      await provider.loadGoalsDashboard(_selectedDate);
      if (!mounted) return;
      setState(() => _voiceState = _VoiceState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (mounted) setState(() => _voiceState = _VoiceState.idle);
    } catch (error) {
      if (mounted) {
        setState(() => _voiceState = _VoiceState.idle);
        _message(error.toString());
      }
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _openFullPlan(PlannerProvider provider) {
    final entries = _tasksForDate(provider.plans, _selectedDate);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 480),
        reverseTransitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (_, animation, __) => _FullDayPlanScreen(
          date: _selectedDate,
          entries: entries,
          recommendation: provider.goalsDashboard?.personalTip ?? '',
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero)
                .animate(animation),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/backgrounds/image2.png', fit: BoxFit.cover),
          SafeArea(
            bottom: false,
            child: Consumer<PlannerProvider>(
              builder: (context, provider, _) {
                final width = MediaQuery.sizeOf(context).width;
                final side = (width * 0.06).clamp(20.0, 30.0);
                return RefreshIndicator(
                  color: _orange,
                  onRefresh: () async {
                    await provider.loadPlans();
                    await provider.loadGoalsDashboard(_selectedDate);
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 18, side, 128),
                        sliver: SliverList.list(
                          children: [
                            _RecommendationsCard(
                              dashboard: provider.goalsDashboard,
                              loading: provider.isGoalsLoading,
                              onViewPlan: () => _openFullPlan(provider),
                            ),
                            const SizedBox(height: 12),
                            _CalendarCard(
                              selectedDate: _selectedDate,
                              windowStart: _calendarWindowStart,
                              plans: provider.plans,
                              editMode: _editMonth,
                              onDateSelected: _selectDate,
                              onPreviousMonth: () => _changeMonth(-1),
                              onNextMonth: () => _changeMonth(1),
                              onToggleEdit: () => setState(() => _editMonth = !_editMonth),
                              onEditAction: (action) => _calendarAction(action, provider),
                            ),
                            const SizedBox(height: 12),
                            _VoiceCommandCard(
                              controller: _commandController,
                              state: _voiceState,
                              levels: _levels,
                              waveController: _waveController,
                              onMic: _toggleRecording,
                              onSend: _sendCommand,
                            ),
                          ],
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

  Future<void> _calendarAction(String action, PlannerProvider provider) async {
    final entries = _tasksForDate(provider.plans, _selectedDate);
    if (action == 'done' && entries.isNotEmpty) {
      for (final entry in entries.where((item) => item.task.status != 'done')) {
        await provider.toggleTaskStatus(entry.plan.id, entry.task.id, 'done');
      }
      await provider.loadGoalsDashboard(_selectedDate);
      return;
    }
    if (action == 'edit' && entries.isNotEmpty) {
      _commandController.text = 'Optimize the plan for ${DateFormat('yyyy-MM-dd').format(_selectedDate)}';
    } else if (action == 'delete' && entries.isNotEmpty) {
      _commandController.text = 'Delete all tasks scheduled for ${DateFormat('yyyy-MM-dd').format(_selectedDate)}';
    } else {
      _commandController.text = 'Create a plan for ${DateFormat('yyyy-MM-dd').format(_selectedDate)}: ';
    }
  }
}

class _RecommendationsCard extends StatelessWidget {
  final DashboardModel? dashboard;
  final bool loading;
  final VoidCallback onViewPlan;

  const _RecommendationsCard({
    super.key,
    required this.dashboard,
    required this.loading,
    required this.onViewPlan,
  });

  @override
  Widget build(BuildContext context) {
    final data = dashboard;
    final summary = data?.summary.isNotEmpty == true
        ? data!.summary
        : 'Your plan and personal focus tips will appear here.';
    return _GlassPanel(
      radius: 34,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('✦', style: TextStyle(color: _orange, fontSize: 27)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AI Recommendations', style: _GoalsText.title),
                      const SizedBox(height: 5),
                      AnimatedOpacity(
                        opacity: loading ? 0.35 : 1,
                        duration: const Duration(milliseconds: 260),
                        child: Text(summary, style: _GoalsText.body),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.more_horiz, size: 22),
              ],
            ),
            const SizedBox(height: 17),
            _RecommendationRow(
              icon: Icons.track_changes_rounded,
              title: 'Focus Block',
              description: 'Your best uninterrupted work window',
              value: '${data?.focusStart ?? '09:00'} – ${data?.focusEnd ?? '12:00'}',
            ),
            _RecommendationRow(
              icon: Icons.bolt_rounded,
              title: 'Keep it short',
              description: data?.personalTip.isNotEmpty == true
                  ? data!.personalTip
                  : 'Break big tasks into smaller steps',
              value: '${data?.mainTasks ?? 0} tasks',
            ),
            _RecommendationRow(
              icon: Icons.coffee_rounded,
              title: 'Take a break',
              description: 'A short pause will protect your focus',
              value: '${data?.breakMinutes ?? 10} min',
            ),
            const SizedBox(height: 7),
            _GlassButton(label: 'View full plan', onTap: onViewPlan),
          ],
        ),
      ),
    );
  }
}

class _RecommendationRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String value;

  const _RecommendationRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          _GoalsGlassCircle(
            size: 49,
            child: Icon(icon, color: _orange, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _GoalsText.itemTitle),
                const SizedBox(height: 2),
                Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: _GoalsText.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _GoalsGlassPill(
            constraints: const BoxConstraints(minWidth: 88),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Text(value, textAlign: TextAlign.center, style: _GoalsText.value),
          ),
        ],
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  final DateTime selectedDate;
  final DateTime windowStart;
  final List<PlanModel> plans;
  final bool editMode;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToggleEdit;
  final ValueChanged<String> onEditAction;

  const _CalendarCard({
    required this.selectedDate,
    required this.windowStart,
    required this.plans,
    required this.editMode,
    required this.onDateSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToggleEdit,
    required this.onEditAction,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 38,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cell = constraints.maxWidth / 7;
            final dates = List<DateTime>.generate(
              28,
              (index) => windowStart.add(Duration(days: index)),
            );
            final today = _dateOnly(DateTime.now());
            Widget day(int index) => SizedBox.square(
                  dimension: cell,
                  child: Padding(
                    padding: const EdgeInsets.all(0.8),
                    child: _CalendarDay(
                      day: dates[index].day,
                      selected: _sameDay(dates[index], selectedDate),
                      past: dates[index].isBefore(today),
                      today: _sameDay(dates[index], today),
                      planned: _isPlannedDay(plans, dates[index]),
                      onTap: () => onDateSelected(dates[index]),
                    ),
                  ),
                );
            return GestureDetector(
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -180) onNextMonth();
                if (velocity > 180) onPreviousMonth();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: cell,
                    child: Row(
                      children: [
                        SizedBox(
                          width: cell * 3,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: cell * 0.12,
                              vertical: cell * 0.15,
                            ),
                            child: _CalendarDatePill(date: selectedDate),
                          ),
                        ),
                        for (var index = 0; index < 4; index++) day(index),
                      ],
                    ),
                  ),
                  for (var row = 0; row < 3; row++)
                    SizedBox(
                      height: cell,
                      child: Row(
                        children: [
                          for (var column = 0; column < 7; column++)
                            day(4 + row * 7 + column),
                        ],
                      ),
                    ),
                  SizedBox(
                    height: cell,
                    child: Row(
                      children: [
                        for (var index = 25; index < 28; index++) day(index),
                        SizedBox(
                          width: cell * 4,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: cell * 0.10,
                              vertical: cell * 0.14,
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 380),
                              child: editMode
                                  ? _MonthEditActions(
                                      key: const ValueKey('month-actions'),
                                      onAction: onEditAction,
                                      onDone: onToggleEdit,
                                    )
                                  : _GlassButton(
                                      key: const ValueKey('edit-month'),
                                      label: 'Edit month',
                                      onTap: onToggleEdit,
                                      dark: true,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CalendarDatePill extends StatelessWidget {
  final DateTime date;

  const _CalendarDatePill({required this.date});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 999,
      child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          child: Container(
            key: ValueKey(date),
            alignment: Alignment.center,
            child: Text(
              _displayDate(date),
              maxLines: 1,
              style: _GoalsText.date,
            ),
          ),
      ),
    );
  }
}

class _MonthEditActions extends StatelessWidget {
  final ValueChanged<String> onAction;
  final VoidCallback onDone;

  const _MonthEditActions({
    super.key,
    required this.onAction,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _dark,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _MonthAction(icon: Icons.add_rounded, onTap: () => onAction('add')),
          _MonthAction(
            icon: Icons.auto_fix_high_rounded,
            onTap: () => onAction('edit'),
          ),
          _MonthAction(icon: Icons.check_rounded, onTap: () => onAction('done')),
          GestureDetector(
            onTap: onDone,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              child: Text('Done', style: _GoalsText.value),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  final int day;
  final bool selected;
  final bool past;
  final bool today;
  final bool planned;
  final VoidCallback onTap;

  const _CalendarDay({
    required this.day,
    required this.selected,
    required this.past,
    required this.today,
    required this.planned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Day $day',
      child: InkResponse(
        onTap: onTap,
        highlightShape: BoxShape.circle,
        splashColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: selected
                ? const RadialGradient(
                    center: Alignment(-0.2, -0.25),
                    radius: 0.86,
                    colors: [Color(0xFFFFB13B), Color(0xFFFF6900)],
                  )
                : past
                    ? const RadialGradient(
                        center: Alignment(-0.25, -0.3),
                        radius: 1,
                        colors: [Color(0xFF372A23), Color(0xFF241B17)],
                      )
                    : RadialGradient(
                        center: const Alignment(-0.3, -0.35),
                        radius: 1,
                        colors: [
                          Colors.white.withOpacity(0.72),
                          Colors.white.withOpacity(0.48),
                        ],
                      ),
            border: Border.all(
              color: selected || today
                  ? const Color(0xFFFF8A00)
                  : Colors.white.withOpacity(0.40),
              width: today && !selected ? 2 : 0.8,
            ),
            boxShadow: selected
                ? [BoxShadow(color: _orange.withOpacity(0.32), blurRadius: 13, spreadRadius: 1)]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (today && !selected)
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _orange, width: 2),
                  ),
                ),
              if (planned && !selected && !today && !past)
                Positioned(
                  bottom: 7,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MonthAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(
          icon,
          size: 17,
          color: _orange,
        ),
      ),
    );
  }
}

class _VoiceCommandCard extends StatelessWidget {
  final TextEditingController controller;
  final _VoiceState state;
  final List<double> levels;
  final AnimationController waveController;
  final VoidCallback onMic;
  final VoidCallback onSend;

  const _VoiceCommandCard({required this.controller, required this.state, required this.levels, required this.waveController, required this.onMic, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 38,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            _VoiceGlassCapsule(
              height: 68,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    _RoundAction(
                      onTap: onMic,
                      active: state == _VoiceState.recording,
                      icon: state == _VoiceState.recording
                          ? Icons.stop_rounded
                          : Icons.mic_rounded,
                    ),
                    const SizedBox(width: 17),
                    Expanded(
                      child: Transform.translate(
                        offset: const Offset(0, 3),
                        child: TextField(
                          controller: controller,
                          style: _GoalsText.input,
                          decoration: const InputDecoration(
                            hintText: 'Add, edit, execute . . .',
                            hintStyle: _GoalsText.hint,
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onSubmitted: (_) => onSend(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _RoundAction(
                      onTap: onSend,
                      icon: Icons.send_rounded,
                      pale: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            _VoiceGlassCapsule(
              height: 63,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 21),
                child: AnimatedBuilder(
                  animation: waveController,
                  builder: (_, __) => CustomPaint(
                    painter: _WavePainter(
                      levels: levels,
                      state: state,
                      phase: waveController.value,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceGlassCapsule extends StatelessWidget {
  final double height;
  final Widget child;

  const _VoiceGlassCapsule({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    final radius = height / 2;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: _GlassPanel(radius: radius, child: child),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> levels;
  final _VoiceState state;
  final double phase;
  const _WavePainter({required this.levels, required this.state, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _orange.withOpacity(state == _VoiceState.idle ? 0.46 : 0.92)..strokeWidth = 1.4..strokeCap = StrokeCap.round;
    final count = levels.length;
    final gap = size.width / (count - 1);
    for (var i = 0; i < count; i++) {
      double level = levels[i];
      if (state == _VoiceState.idle) level = 0.16 + math.sin(i * 0.7) * 0.05;
      if (state == _VoiceState.processing) level = 0.18 + 0.62 * ((math.sin(i * 0.44 - phase * math.pi * 2) + 1) / 2);
      if (state == _VoiceState.ready) level = 0.16 + 0.6 * math.exp(-math.pow((i - count / 2) / 6, 2));
      final height = (size.height * level).clamp(5.0, size.height - 8);
      final x = i * gap;
      canvas.drawLine(Offset(x, (size.height - height) / 2), Offset(x, (size.height + height) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => true;
}

class _RoundAction extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final bool active;
  final bool pale;
  const _RoundAction({required this.onTap, required this.icon, this.active = false, this.pale = false});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: AnimatedScale(
        scale: active ? 1.035 : 1,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        child: SizedBox.square(
          dimension: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.055),
                  blurRadius: 12,
                  spreadRadius: -5,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: _orange.withOpacity(active ? 0.34 : 0.12),
                  blurRadius: active ? 22 : 14,
                  spreadRadius: active ? 1 : -5,
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
                          colors: pale
                              ? [
                                  Colors.white.withOpacity(0.48),
                                  const Color(0xFFFFC89D).withOpacity(0.42),
                                ]
                              : const [
                                  Color(0xFFFF6C22),
                                  Color(0xFFFFA000),
                                ],
                        ),
                      ),
                    ),
                    CustomPaint(
                      painter: const _GoalsGlassEdgePainter(radius: 28),
                    ),
                    Center(
                      child: Icon(
                        icon,
                        color: _dark.withOpacity(0.52),
                        size: 25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  const _GlassPanel({required this.child, required this.radius});

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
                        Colors.white.withOpacity(0.19),
                        Colors.white.withOpacity(0.055),
                        const Color(0xFFFFB04A).withOpacity(0.035),
                        Colors.white.withOpacity(0.105),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GoalsGlassEdgePainter(radius: radius),
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

class _GoalsGlassCircle extends StatelessWidget {
  final double size;
  final Widget child;

  const _GoalsGlassCircle({required this.size, required this.child});

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
              color: _orange.withOpacity(0.12),
              blurRadius: 14,
              spreadRadius: -5,
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
                      colors: [
                        Colors.white.withOpacity(0.46),
                        const Color(0xFFF1B97C).withOpacity(0.30),
                      ],
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _GoalsGlassEdgePainter(radius: size / 2),
                ),
                Center(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalsGlassPill extends StatelessWidget {
  final BoxConstraints constraints;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _GoalsGlassPill({
    required this.constraints,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 999,
      child: ConstrainedBox(
        constraints: constraints,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _GoalsGlassEdgePainter extends CustomPainter {
  final double radius;

  const _GoalsGlassEdgePainter({required this.radius});

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
  bool shouldRepaint(covariant _GoalsGlassEdgePainter oldDelegate) {
    return oldDelegate.radius != radius;
  }
}

class _GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool dark;
  const _GlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: dark ? _dark : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              label,
              style: _GoalsText.button.copyWith(
                color: dark ? _orange : _dark,
              ),
            ),
          ),
        ),
      ),
    );
    if (dark) {
      return content;
    }
    return _GlassPanel(radius: 999, child: content);
  }
}

class _FullDayPlanScreen extends StatefulWidget {
  final DateTime date;
  final List<_TaskEntry> entries;
  final String recommendation;
  const _FullDayPlanScreen({required this.date, required this.entries, required this.recommendation});

  @override
  State<_FullDayPlanScreen> createState() => _FullDayPlanScreenState();
}

class _FullDayPlanScreenState extends State<_FullDayPlanScreen> {
  late List<_TaskEntry> _entries;
  @override
  void initState() { super.initState(); _entries = [...widget.entries]..sort(_entrySort); }

  Future<void> _toggleTask(int index) async {
    final previous = _entries[index];
    final nextStatus = previous.task.status == 'done' ? 'pending' : 'done';
    setState(() {
      _entries[index] = _TaskEntry(
        previous.plan,
        previous.task.copyWith(status: nextStatus),
      );
    });
    try {
      await context.read<PlannerProvider>().toggleTaskStatus(
            previous.plan.id,
            previous.task.id,
            nextStatus,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() => _entries[index] = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the task: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/backgrounds/image2.png', fit: BoxFit.cover),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 22, 8),
                  child: Row(children: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)), Expanded(child: Text(DateFormat('MMMM d').format(widget.date), style: _GoalsText.title)), const Text('Full plan', style: _GoalsText.body)]),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                    itemCount: math.max(_entries.length, 1),
                    onReorder: (oldIndex, newIndex) { setState(() { if (newIndex > oldIndex) newIndex--; final item = _entries.removeAt(oldIndex); _entries.insert(newIndex, item); }); },
                    itemBuilder: (context, index) {
                      if (_entries.isEmpty) return const _EmptyPlanCard(key: ValueKey('empty'));
                      final entry = _entries[index];
                      return Padding(
                        key: ValueKey('${entry.plan.id}_${entry.task.id}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FullTaskCard(
                          entry: entry,
                          order: index + 1,
                          onToggle: () => _toggleTask(index),
                        ),
                      );
                    },
                    header: widget.recommendation.isEmpty ? null : Padding(padding: const EdgeInsets.only(bottom: 14), child: _GlassPanel(radius: 28, child: Padding(padding: const EdgeInsets.all(18), child: Text('AI: ${widget.recommendation}', style: _GoalsText.body)))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullTaskCard extends StatelessWidget {
  final _TaskEntry entry;
  final int order;
  final VoidCallback onToggle;
  const _FullTaskCard({
    required this.entry,
    required this.order,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final task = entry.task;
    final scheduled = DateTime.tryParse(task.scheduledAt ?? '');
    return _GlassPanel(
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            InkResponse(
              onTap: onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: task.status == 'done' ? _dark : _orange,
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      task.status == 'done' ? '✓' : '$order',
                      key: ValueKey(task.status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: AppTypography.family,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(task.title, style: _GoalsText.itemTitle.copyWith(decoration: task.status == 'done' ? TextDecoration.lineThrough : null)),
                if (task.description.isNotEmpty) Text(task.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: _GoalsText.caption),
                const SizedBox(height: 5),
                Text('${scheduled == null ? 'Any time' : DateFormat('HH:mm').format(scheduled)}  •  ${task.priority} priority  •  ${task.estimatedMin} min', style: _GoalsText.meta),
                if (entry.plan.notes.isNotEmpty) Text(entry.plan.notes, maxLines: 1, overflow: TextOverflow.ellipsis, style: _GoalsText.meta),
              ]),
            ),
            const Icon(Icons.drag_handle_rounded, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlanCard extends StatelessWidget {
  const _EmptyPlanCard({super.key});
  @override
  Widget build(BuildContext context) => _GlassPanel(radius: 30, child: const SizedBox(height: 160, child: Center(child: Text('No tasks planned for this day', style: _GoalsText.body))));
}

class _GoalsText {
  static const title = TextStyle(fontFamily: AppTypography.family, fontSize: 21, fontWeight: FontWeight.w500, letterSpacing: -0.85, height: 1.05);
  static const body = TextStyle(fontFamily: AppTypography.family, fontSize: 14, fontWeight: FontWeight.w300, letterSpacing: -0.45, height: 1.35);
  static const itemTitle = TextStyle(fontFamily: AppTypography.family, fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.5, height: 1.15);
  static const caption = TextStyle(fontFamily: AppTypography.family, fontSize: 12.5, fontWeight: FontWeight.w300, letterSpacing: -0.35, height: 1.25, color: Color(0xB3000000));
  static const value = TextStyle(fontFamily: AppTypography.family, fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: -0.4, color: _orange);
  static const date = TextStyle(fontFamily: AppTypography.family, fontSize: 21, fontWeight: FontWeight.w300, letterSpacing: -0.8);
  static const button = TextStyle(fontFamily: AppTypography.family, fontSize: 16, fontWeight: FontWeight.w300, letterSpacing: -0.55);
  static const input = TextStyle(fontFamily: AppTypography.family, fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.82);
  static const hint = TextStyle(fontFamily: AppTypography.family, fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.82, color: Color(0x66000000));
  static const meta = TextStyle(fontFamily: AppTypography.family, fontSize: 10.5, fontWeight: FontWeight.w300, color: Colors.black45);
}

class _TaskEntry {
  final PlanModel plan;
  final TaskModel task;
  const _TaskEntry(this.plan, this.task);
}

List<_TaskEntry> _tasksForDate(List<PlanModel> plans, DateTime date) {
  final result = <_TaskEntry>[];
  for (final plan in plans) {
    for (final task in plan.structuredPlan) {
      final taskDate = DateTime.tryParse(task.scheduledAt ?? '') ?? DateTime.tryParse(task.deadline ?? '') ?? plan.createdAt;
      if (_sameDay(taskDate.toLocal(), date)) result.add(_TaskEntry(plan, task));
    }
  }
  return result;
}

bool _isPlannedDay(List<PlanModel> plans, DateTime date) {
  final entries = _tasksForDate(plans, date);
  return entries.isNotEmpty &&
      entries.any((entry) => entry.task.status != 'done');
}

int _entrySort(_TaskEntry a, _TaskEntry b) {
  const rank = {'high': 0, 'medium': 1, 'low': 2};
  final priority = (rank[a.task.priority] ?? 3).compareTo(rank[b.task.priority] ?? 3);
  if (priority != 0) return priority;
  return (a.task.scheduledAt ?? '').compareTo(b.task.scheduledAt ?? '');
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _displayDate(DateTime date) {
  final suffix = switch (date.day) { 1 || 21 || 31 => 'st', 2 || 22 => 'nd', 3 || 23 => 'rd', _ => 'th' };
  return '${DateFormat('MMMM').format(date)} ${date.day}$suffix';
}
