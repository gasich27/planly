import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/models/plan_model.dart';
import '../core/models/story_branch_model.dart';
import '../core/models/task_model.dart';
import '../theme/app_theme.dart';

const _storyOrange = Color(0xFFFF7A35);
const _storyAmber = Color(0xFFFFB900);

class PlanningStoryBranch {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final String grouping;
  final bool isCustom;

  const PlanningStoryBranch({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.grouping,
    this.isCustom = false,
  });

  factory PlanningStoryBranch.custom(StoryBranchModel branch) {
    return PlanningStoryBranch(
      id: branch.id,
      title: branch.title,
      startDate: branch.startDate,
      endDate: branch.endDate,
      grouping: branch.grouping,
      isCustom: true,
    );
  }

  static List<PlanningStoryBranch> defaults(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    return <PlanningStoryBranch>[
      PlanningStoryBranch(
        id: 'today',
        title: 'Today',
        startDate: today,
        endDate: today,
        grouping: 'hour',
      ),
      PlanningStoryBranch(
        id: 'tomorrow',
        title: 'Tomorrow',
        startDate: tomorrow,
        endDate: tomorrow,
        grouping: 'hour',
      ),
      PlanningStoryBranch(
        id: 'week',
        title: 'Week',
        startDate: today,
        endDate: today.add(const Duration(days: 6)),
        grouping: 'day',
      ),
      PlanningStoryBranch(
        id: 'month',
        title: 'Month',
        startDate: DateTime(now.year, now.month),
        endDate: monthEnd,
        grouping: 'week',
      ),
    ];
  }
}

class PlanningStoriesStrip extends StatefulWidget {
  final List<StoryBranchModel> customBranches;
  final VoidCallback onAddPlan;
  final VoidCallback onEditPlan;
  final VoidCallback onCreateBranch;
  final ValueChanged<PlanningStoryBranch> onOpenBranch;

  const PlanningStoriesStrip({
    super.key,
    required this.customBranches,
    required this.onAddPlan,
    required this.onEditPlan,
    required this.onCreateBranch,
    required this.onOpenBranch,
  });

  @override
  State<PlanningStoriesStrip> createState() => _PlanningStoriesStripState();
}

class _PlanningStoriesStripState extends State<PlanningStoriesStrip> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant PlanningStoriesStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customBranches.length > oldWidget.customBranches.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 620),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseBranches = PlanningStoryBranch.defaults(DateTime.now())
        .where((branch) => branch.id != 'today')
        .toList();
    final customBranches =
        widget.customBranches.map(PlanningStoryBranch.custom).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        const sidePadding = 28.0;
        final available = constraints.maxWidth - sidePadding * 2;
        final storySlotWidth = available / 6;
        final spacing = (storySlotWidth - 56).clamp(6.0, 14.0).toDouble();
        return SizedBox(
          height: 98,
          child: ListView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: sidePadding),
            children: [
              SizedBox(
                key: const Key('base_stories_group'),
                width: available,
                child: _BaseStoriesGroup(
                  branches: baseBranches,
                  onAddPlan: widget.onAddPlan,
                  onEditPlan: widget.onEditPlan,
                  onCreateBranch: widget.onCreateBranch,
                  onOpenBranch: widget.onOpenBranch,
                ),
              ),
              for (var index = 0; index < customBranches.length; index++) ...[
                SizedBox(width: spacing),
                _BranchStory(
                  branch: customBranches[index],
                  visualIndex: index + baseBranches.length,
                  onTap: () => widget.onOpenBranch(customBranches[index]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BaseStoriesGroup extends StatelessWidget {
  final List<PlanningStoryBranch> branches;
  final VoidCallback onAddPlan;
  final VoidCallback onEditPlan;
  final VoidCallback onCreateBranch;
  final ValueChanged<PlanningStoryBranch> onOpenBranch;

  const _BaseStoriesGroup({
    required this.branches,
    required this.onAddPlan,
    required this.onEditPlan,
    required this.onCreateBranch,
    required this.onOpenBranch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Center(
            child: _PlanActionStory(
              label: 'add plan',
              palette: const [Color(0xFFF2F2F2), Color(0xFFF1D58D)],
              pillColor: const Color(0xFFFFF5E5),
              onTap: onAddPlan,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _PlanActionStory(
              label: 'edit plan',
              palette: const [Color(0xFFF4F4F4), Color(0xFFFFB5A6)],
              pillColor: const Color(0xFFFFE8E7),
              onTap: onEditPlan,
            ),
          ),
        ),
        Expanded(
          child: Center(child: _NewBranchButton(onTap: onCreateBranch)),
        ),
        for (var index = 0; index < branches.length; index++)
          Expanded(
            child: Center(
              child: _BranchStory(
                branch: branches[index],
                visualIndex: index,
                onTap: () => onOpenBranch(branches[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlanActionStory extends StatelessWidget {
  final String label;
  final List<Color> palette;
  final Color pillColor;
  final VoidCallback onTap;

  const _PlanActionStory({
    required this.label,
    required this.palette,
    required this.pillColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 58,
        height: 94,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Container(
              width: 54,
              height: 54,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFAD7D), width: 2),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: palette,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 49,
              child: Container(
                height: 25,
                constraints: const BoxConstraints(minWidth: 58),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pillColor.withOpacity(0.88),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: AppTypography.family,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.45,
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

class _NewBranchButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NewBranchButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 82,
      child: Align(
        alignment: const Alignment(0, -0.42),
        child: GestureDetector(
          key: const Key('create_story_branch'),
          onTap: onTap,
          child: Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFD89B), Color(0xFFFFB98E)],
              ),
            ),
            child:
                const Icon(Icons.add_rounded, size: 18, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}

class _BranchStory extends StatelessWidget {
  final PlanningStoryBranch branch;
  final int visualIndex;
  final VoidCallback onTap;

  const _BranchStory({
    required this.branch,
    required this.visualIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.22),
                border: Border.all(color: _storyOrange, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _storyOrange.withOpacity(0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(child: _StoryArtwork(index: visualIndex)),
            ),
            const SizedBox(height: 6),
            Text(
              branch.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTypography.family,
                fontSize: 10.5,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryArtwork extends StatelessWidget {
  final int index;

  const _StoryArtwork({required this.index});

  @override
  Widget build(BuildContext context) {
    final palettes = <List<Color>>[
      const [Color(0xFFFFFAE8), Color(0xFFFFD9B9), Color(0xFFFF4B16)],
      const [Color(0xFFFFA429), Color(0xFFFFE6C7), Color(0xFFFF356F)],
      const [Color(0xFFFFFAF3), Color(0xFFFF5A00), Color(0xFFFF9A57)],
      const [Color(0xFFFFD09A), Color(0xFFFF7040), Color(0xFFFFF1DF)],
    ];
    final colors = palettes[index % palettes.length];
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
        Positioned(
          left: index.isEven ? -10 : 25,
          top: index.isEven ? 26 : -8,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF4B00).withOpacity(0.86),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PlanCommandResult {
  final String command;
  final String period;
  final DateTimeRange dateRange;
  final String branchId;
  final String branchTitle;
  final String grouping;
  final String placement;

  const PlanCommandResult({
    required this.command,
    required this.period,
    required this.dateRange,
    required this.branchId,
    required this.branchTitle,
    required this.grouping,
    required this.placement,
  });
}

Future<PlanCommandResult?> showPlanCommandEditor(
  BuildContext context, {
  required bool isEdit,
  required List<PlanningStoryBranch> branches,
  PlanningStoryBranch? selectedBranch,
  required Future<String> Function(File audio) transcribeAudio,
}) async {
  return showModalBottomSheet<PlanCommandResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xFFFFB978).withOpacity(0.34),
    builder: (context) => _EditorSheetBackdrop(
      child: _PlanCommandSheet(
        isEdit: isEdit,
        branches: branches,
        selectedBranch: selectedBranch,
        transcribeAudio: transcribeAudio,
      ),
    ),
  );
}

class _PlanCommandSheet extends StatefulWidget {
  final bool isEdit;
  final List<PlanningStoryBranch> branches;
  final PlanningStoryBranch? selectedBranch;
  final Future<String> Function(File audio) transcribeAudio;

  const _PlanCommandSheet({
    required this.isEdit,
    required this.branches,
    required this.selectedBranch,
    required this.transcribeAudio,
  });

  @override
  State<_PlanCommandSheet> createState() => _PlanCommandSheetState();
}

class _PlanCommandSheetState extends State<_PlanCommandSheet> {
  final _commandController = TextEditingController();
  final _nameController = TextEditingController();
  final _recorder = AudioRecorder();
  late PlanningStoryBranch _branch;
  late DateTimeRange _range;
  late String _grouping;
  String _placement = 'inside';
  bool _recording = false;
  bool _transcribing = false;

  @override
  void initState() {
    super.initState();
    _branch = widget.selectedBranch ?? widget.branches.first;
    _range = DateTimeRange(start: _branch.startDate, end: _branch.endDate);
    _grouping = _branch.grouping;
    _nameController.text = _branch.title;
  }

  @override
  void dispose() {
    _commandController.dispose();
    _nameController.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _transcribing = path != null;
      });
      if (path == null) return;
      try {
        final transcript = await widget.transcribeAudio(File(path));
        if (mounted) _commandController.text = transcript;
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
        }
      } finally {
        if (mounted) setState(() => _transcribing = false);
      }
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice input is available on iOS and Android.')),
      );
      return;
    }
    if (!await _recorder.hasPermission()) return;
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/planly_editor_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _selectRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDateRange: _range,
    );
    if (selected != null && mounted) setState(() => _range = selected);
  }

  void _submit() {
    final command = _commandController.text.trim();
    if (command.isEmpty || _transcribing) return;
    Navigator.pop(
      context,
      PlanCommandResult(
        command: command,
        period: _periodFor(_grouping),
        dateRange: _range,
        branchId: _branch.id,
        branchTitle: _nameController.text.trim().isEmpty
            ? _branch.title
            : _nameController.text.trim(),
        grouping: _grouping,
        placement: _placement,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.93),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            28,
            12,
            28,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 14),
              _EditorGlassPanel(
                radius: 38,
                child: SizedBox(
                  height: (height * 0.24).clamp(180.0, 235.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _EditorMicButton(
                        recording: _recording,
                        loading: _transcribing,
                        onTap: _toggleRecording,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          key: const Key('plan_command_input'),
                          controller: _commandController,
                          autofocus: true,
                          expands: true,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          style: _editorTextStyle(17),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.only(top: 18),
                            border: InputBorder.none,
                            hintText: widget.isEdit
                                ? 'Describe what should be changed . . .'
                                : 'Add the story outline to the thread . . .',
                            hintStyle: _editorTextStyle(17, opacity: 0.40),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _EditorGlassPanel(
                radius: 38,
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      key: const Key('plan_branch_selector'),
                      initialValue: _branch.id,
                      decoration: _glassFieldDecoration('Name'),
                      borderRadius: BorderRadius.circular(14),
                      style: _editorTextStyle(15),
                      items: widget.branches
                          .map((branch) => DropdownMenuItem(
                                value: branch.id,
                                child: Text(branch.title),
                              ))
                          .toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        final branch = widget.branches.firstWhere((item) => item.id == id);
                        setState(() {
                          _branch = branch;
                          _nameController.text = branch.title;
                          _range = DateTimeRange(start: branch.startDate, end: branch.endDate);
                          _grouping = branch.grouping;
                        });
                      },
                    ),
                    if (widget.isEdit) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nameController,
                        style: _editorTextStyle(15),
                        decoration: _glassFieldDecoration('Rename branch'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: const Key('plan_grouping_selector'),
                      initialValue: _grouping,
                      decoration: _glassFieldDecoration('Planning period'),
                      borderRadius: BorderRadius.circular(14),
                      style: _editorTextStyle(15),
                      items: const [
                        DropdownMenuItem(value: 'hour', child: Text('By hours')),
                        DropdownMenuItem(value: 'day', child: Text('By days')),
                        DropdownMenuItem(value: 'week', child: Text('By weeks')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _grouping = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    _GradientDateField(
                      range: _range,
                      label: 'Date range',
                      onTap: _selectRange,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _placement,
                      decoration: _glassFieldDecoration(widget.isEdit ? 'Replace where' : 'Add where'),
                      borderRadius: BorderRadius.circular(14),
                      style: _editorTextStyle(15),
                      items: const [
                        DropdownMenuItem(value: 'before', child: Text('Before selected dates')),
                        DropdownMenuItem(value: 'inside', child: Text('Inside selected dates')),
                        DropdownMenuItem(value: 'after', child: Text('After selected dates')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _placement = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    _GradientActionButton(
                      label: widget.isEdit ? 'Edit plan' : 'Add plan',
                      onTap: _submit,
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

String _periodFor(String grouping) => switch (grouping) {
      'hour' => 'day',
      'week' => 'month',
      _ => 'week',
    };

Widget _sheetHandle() => Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(99),
      ),
    );

TextStyle _editorTextStyle(double size, {double opacity = 1}) => TextStyle(
      fontFamily: AppTypography.family,
      fontSize: size,
      fontWeight: FontWeight.w300,
      color: Colors.black.withOpacity(opacity),
      letterSpacing: -size * 0.04,
    );

class _EditorMicButton extends StatelessWidget {
  final bool recording;
  final bool loading;
  final VoidCallback onTap;

  const _EditorMicButton({required this.recording, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFFFF6D36), Color(0xFFFFA000)]),
          boxShadow: recording
              ? [BoxShadow(color: _storyOrange.withOpacity(0.42), blurRadius: 22, spreadRadius: 5)]
              : null,
        ),
        child: loading
            ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black38))
            : Icon(recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.black.withOpacity(0.36)),
      ),
    );
  }
}

class _EditorGlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  const _EditorGlassPanel({required this.child, required this.radius, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 22,
            spreadRadius: -8,
            offset: const Offset(0, 10),
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
                        const Color(0xFFFFE7C4).withOpacity(0.38),
                        const Color(0xFFFFDBAA).withOpacity(0.18),
                        const Color(0xFFFFC978).withOpacity(0.12),
                        const Color(0xFFFFE7C4).withOpacity(0.28),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _EditorGlassEdgePainter(radius: radius),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorSheetBackdrop extends StatelessWidget {
  final Widget child;

  const _EditorSheetBackdrop({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: const SizedBox.expand(),
          ),
        ),
        child,
      ],
    );
  }
}

class _EditorGlassEdgePainter extends CustomPainter {
  final double radius;

  const _EditorGlassEdgePainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge = RRect.fromRectAndRadius(
      rect.deflate(0.7),
      Radius.circular(math.max(0, radius - 0.7)),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..shader = const LinearGradient(
        begin: Alignment(-0.9, -1),
        end: Alignment(0.95, 1),
        stops: [0, 0.28, 0.62, 1],
        colors: [
          Color(0xA8FFE7C4),
          Color(0x50FFDBAA),
          Color(0x22FFC978),
          Color(0x82FFE7C4),
        ],
      ).createShader(rect);
    canvas.drawRRect(edge, paint);
  }

  @override
  bool shouldRepaint(covariant _EditorGlassEdgePainter oldDelegate) {
    return oldDelegate.radius != radius;
  }
}

class _PlanlyEditorSurface extends StatelessWidget {
  final TextEditingController commandController;
  final String commandHint;
  final List<Widget> children;

  const _PlanlyEditorSurface({
    required this.commandController,
    required this.commandHint,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.92),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            28,
            12,
            28,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 14),
              _EditorGlassPanel(
                radius: 38,
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  height: (height * 0.24).clamp(180.0, 235.0),
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0xFFFF7137), Color(0xFFFFA000)],
                        ),
                      ),
                      child: Icon(Icons.mic_rounded,
                          color: Colors.black.withOpacity(0.34)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: commandController,
                        autofocus: true,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: _editorTextStyle(17),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          contentPadding: const EdgeInsets.only(top: 18),
                          hintText: commandHint,
                          hintStyle: _editorTextStyle(17, opacity: 0.42),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
              const SizedBox(height: 16),
              _EditorGlassPanel(
                radius: 38,
                padding: const EdgeInsets.all(10),
                child: Column(children: children),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientDateField extends StatelessWidget {
  final DateTimeRange range;
  final String label;
  final VoidCallback onTap;

  const _GradientDateField({
    required this.range,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: _gradientFieldDecorationBox(),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${DateFormat('dd.MM.yyyy').format(range.start)} - ${DateFormat('dd.MM.yyyy').format(range.end)}',
                style: _editorTextStyle(15),
              ),
            ),
            Text(
              label,
              style: _editorTextStyle(14, opacity: 0.62),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GradientActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey<String>('editor_action_$label'),
      onTap: onTap,
      child: Container(
        height: 74,
        alignment: Alignment.center,
        decoration: _gradientFieldDecorationBox(),
        child: Text(
          label,
          style: _editorTextStyle(24).copyWith(fontWeight: FontWeight.w300),
        ),
      ),
    );
  }
}

InputDecoration _gradientFieldDecoration(String label) {
  return _glassFieldDecoration(label);
}

InputDecoration _glassFieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFFFE7C4).withOpacity(0.22),
    labelStyle: _editorTextStyle(15, opacity: 0.62),
    contentPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(
        color: const Color(0xFFFFE7C4).withOpacity(0.58),
        width: 0.8,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(
        color: const Color(0xFFFFE7C4).withOpacity(0.58),
        width: 0.8,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(
        color: const Color(0xFFFFE7C4).withOpacity(0.82),
        width: 0.9,
      ),
    ),
  );
}

BoxDecoration _gradientFieldDecorationBox() {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: const Alignment(-0.9, -1),
      end: const Alignment(0.9, 1),
      stops: const [0, 0.34, 0.72, 1],
      colors: [
        const Color(0xFFFFE7C4).withOpacity(0.30),
        const Color(0xFFFFDBAA).withOpacity(0.13),
        const Color(0xFFFFC978).withOpacity(0.10),
        const Color(0xFFFFE7C4).withOpacity(0.20),
      ],
    ),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(
      color: const Color(0xFFFFE7C4).withOpacity(0.58),
      width: 0.8,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.045),
        blurRadius: 16,
        spreadRadius: -8,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

Future<StoryBranchModel?> showPlanlyStoryBranchEditor(
  BuildContext context, {
  StoryBranchModel? initial,
}) async {
  final commandController =
      TextEditingController(text: initial?.description ?? '');
  final titleController = TextEditingController(text: initial?.title ?? '');
  var start = initial?.startDate ?? DateTime.now();
  var end = initial?.endDate ?? DateTime.now().add(const Duration(days: 2));
  var grouping = initial?.grouping ?? 'day';
  final result = await showModalBottomSheet<StoryBranchModel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xFFFFB978).withOpacity(0.34),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) {
        Future<void> selectRange() async {
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now().add(const Duration(days: 3650)),
            initialDateRange: DateTimeRange(start: start, end: end),
          );
          if (range != null) {
            setModalState(() {
              start = range.start;
              end = range.end;
            });
          }
        }

        return _EditorSheetBackdrop(
          child: _PlanlyEditorSurface(
            commandController: commandController,
            commandHint: 'Describe your new story branch . . .',
            children: [
            TextField(
              controller: titleController,
              style: _editorTextStyle(15),
              decoration: _gradientFieldDecoration('Name, for example Berlin'),
            ),
            const SizedBox(height: 13),
            _GradientDateField(
              range: DateTimeRange(start: start, end: end),
              label: 'Date range',
              onTap: selectRange,
            ),
            const SizedBox(height: 13),
            DropdownButtonFormField<String>(
              initialValue: grouping,
              decoration: _gradientFieldDecoration('Split stories by'),
              borderRadius: BorderRadius.circular(14),
              style: _editorTextStyle(15),
              items: const [
                DropdownMenuItem(value: 'hour', child: Text('Hours')),
                DropdownMenuItem(value: 'day', child: Text('Days')),
                DropdownMenuItem(value: 'week', child: Text('Weeks')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setModalState(() => grouping = value);
                }
              },
            ),
            const SizedBox(height: 13),
            _GradientActionButton(
              label: initial == null ? 'Add story branch' : 'Save story branch',
              onTap: () {
                final title = titleController.text.trim();
                if (title.isEmpty) {
                  return;
                }
                Navigator.pop(
                  context,
                  StoryBranchModel(
                    id: initial?.id ??
                        'branch_${DateTime.now().microsecondsSinceEpoch}',
                    title: title,
                    startDate: start,
                    endDate: end,
                    grouping: grouping,
                    description: commandController.text.trim(),
                  ),
                );
              },
            ),
            ],
          ),
        );
      },
    ),
  );
  return result;
}

Future<StoryBranchModel?> showStoryBranchEditor(
  BuildContext context, {
  StoryBranchModel? initial,
}) async {
  final titleController = TextEditingController(text: initial?.title ?? '');
  var start = initial?.startDate ?? DateTime.now();
  var end = initial?.endDate ?? DateTime.now().add(const Duration(days: 2));
  var grouping = initial?.grouping ?? 'day';
  final result = await showModalBottomSheet<StoryBranchModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) {
        Future<void> selectRange() async {
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now().add(const Duration(days: 3650)),
            initialDateRange: DateTimeRange(start: start, end: end),
          );
          if (range != null) {
            setModalState(() {
              start = range.start;
              end = range.end;
            });
          }
        }

        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.90),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(36)),
                  border: Border.all(color: Colors.white),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        initial == null
                            ? 'New story branch'
                            : 'Edit story branch',
                        style: const TextStyle(
                          fontFamily: AppTypography.family,
                          fontSize: 25,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -1.2,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: titleController,
                        autofocus: initial == null,
                        decoration:
                            _fieldDecoration('Name, for example Berlin'),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: selectRange,
                        borderRadius: BorderRadius.circular(20),
                        child: InputDecorator(
                          decoration: _fieldDecoration('Date range'),
                          child: Text(
                            '${DateFormat('dd.MM.yyyy').format(start)}  –  ${DateFormat('dd.MM.yyyy').format(end)}',
                            style: const TextStyle(
                                fontFamily: AppTypography.family),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: grouping,
                        decoration: _fieldDecoration('Split stories by'),
                        borderRadius: BorderRadius.circular(20),
                        items: const [
                          DropdownMenuItem(value: 'hour', child: Text('Hours')),
                          DropdownMenuItem(value: 'day', child: Text('Days')),
                          DropdownMenuItem(value: 'week', child: Text('Weeks')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setModalState(() => grouping = value);
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _storyOrange,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          onPressed: () {
                            final title = titleController.text.trim();
                            if (title.isEmpty) {
                              return;
                            }
                            Navigator.pop(
                              context,
                              StoryBranchModel(
                                id: initial?.id ??
                                    'branch_${DateTime.now().microsecondsSinceEpoch}',
                                title: title,
                                startDate: start,
                                endDate: end,
                                grouping: grouping,
                              ),
                            );
                          },
                          child: Text(
                            initial == null ? 'Create branch' : 'Save changes',
                            style: const TextStyle(
                              fontFamily: AppTypography.family,
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  return result;
}

InputDecoration _fieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFFFF4E6),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    ),
  );
}

class PlanningStoryViewerScreen extends StatefulWidget {
  final PlanningStoryBranch branch;
  final List<PlanModel> plans;

  const PlanningStoryViewerScreen({
    super.key,
    required this.branch,
    required this.plans,
  });

  @override
  State<PlanningStoryViewerScreen> createState() =>
      _PlanningStoryViewerScreenState();
}

class _PlanningStoryViewerScreenState extends State<PlanningStoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _timer;
  late final List<_StorySegment> _segments;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _segments = _buildSegments(widget.branch, widget.plans);
    _pageController = PageController();
    _timer =
        AnimationController(vsync: this, duration: const Duration(seconds: 7))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _next();
            }
          });
    _timer.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _timer.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= _segments.length - 1) {
      Navigator.maybePop(context);
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 430),
      curve: Curves.easeOutCubic,
    );
  }

  void _previous() {
    if (_index == 0) {
      Navigator.maybePop(context);
      return;
    }
    _pageController.previousPage(
      duration: const Duration(milliseconds: 430),
      curve: Curves.easeOutCubic,
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
          PageView.builder(
            controller: _pageController,
            itemCount: _segments.length,
            onPageChanged: (value) {
              setState(() => _index = value);
              _timer
                ..reset()
                ..forward();
            },
            itemBuilder: (context, index) => _StoryPage(
              branch: widget.branch,
              segment: _segments[index],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
                  child: AnimatedBuilder(
                    animation: _timer,
                    builder: (context, child) => Row(
                      children: List.generate(_segments.length, (segmentIndex) {
                        final value = segmentIndex < _index
                            ? 1.0
                            : segmentIndex == _index
                                ? _timer.value
                                : 0.0;
                        return Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.42),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: value,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                              colors: [_storyOrange, _storyAmber]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.branch.title,
                          style: const TextStyle(
                            fontFamily: AppTypography.family,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            top: 82,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _previous,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _next,
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

class _StoryPage extends StatelessWidget {
  final PlanningStoryBranch branch;
  final _StorySegment segment;

  const _StoryPage({required this.branch, required this.segment});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 105, 28, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Text(
              segment.title,
              style: const TextStyle(
                fontFamily: AppTypography.family,
                fontSize: 44,
                height: 0.95,
                fontWeight: FontWeight.w400,
                letterSpacing: -2.5,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              segment.subtitle,
              style: TextStyle(
                fontFamily: AppTypography.family,
                fontSize: 14,
                color: Colors.black.withOpacity(0.48),
              ),
            ),
            const SizedBox(height: 28),
            if (segment.tasks.isEmpty)
              _StoryGlassCard(
                child: SizedBox(
                  height: 118,
                  child: Center(
                    child: Text(
                      'No tasks in this part of the plan',
                      style: TextStyle(
                        fontFamily: AppTypography.family,
                        color: Colors.black.withOpacity(0.45),
                      ),
                    ),
                  ),
                ),
              )
            else
              ...segment.tasks.take(5).map(
                    (task) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _StoryTaskCard(task: task),
                    ),
                  ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

class _StoryTaskCard extends StatelessWidget {
  final TaskModel task;

  const _StoryTaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final details =
        task.description.isNotEmpty ? task.description : task.tags.join(', ');
    return _StoryGlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [_storyOrange, _storyAmber]),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.family,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.family,
                        fontSize: 11,
                        color: Colors.black.withOpacity(0.44),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryGlassCard extends StatelessWidget {
  final Widget child;

  const _StoryGlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.32),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.76)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StorySegment {
  final String title;
  final String subtitle;
  final List<TaskModel> tasks;

  const _StorySegment({
    required this.title,
    required this.subtitle,
    required this.tasks,
  });
}

List<_StorySegment> _buildSegments(
  PlanningStoryBranch branch,
  List<PlanModel> plans,
) {
  final entries = <({TaskModel task, DateTime date, bool hasTime})>[];
  for (final plan in plans) {
    for (final task in plan.structuredPlan) {
      final scheduled = DateTime.tryParse(task.scheduledAt ?? '')?.toLocal();
      final deadline = DateTime.tryParse(task.deadline ?? '')?.toLocal();
      final date = scheduled ?? deadline ?? plan.createdAt.toLocal();
      entries.add((task: task, date: date, hasTime: scheduled != null));
    }
  }
  if (branch.grouping == 'hour') {
    return _hourSegments(branch, entries);
  }
  if (branch.grouping == 'week') {
    return _weekSegments(branch, entries);
  }
  return _daySegments(branch, entries);
}

List<_StorySegment> _hourSegments(
  PlanningStoryBranch branch,
  List<({TaskModel task, DateTime date, bool hasTime})> entries,
) {
  final inRange = entries
      .where((entry) => _sameDate(entry.date, branch.startDate))
      .toList();
  final hours = inRange
      .where((entry) => entry.hasTime)
      .map((entry) => entry.date.hour)
      .toSet()
      .toList()
    ..sort();
  final result = <_StorySegment>[];
  for (final hour in hours) {
    result.add(
      _StorySegment(
        title: '${hour.toString().padLeft(2, '0')}:00',
        subtitle: DateFormat('EEEE, MMMM d').format(branch.startDate),
        tasks: inRange
            .where((entry) => entry.hasTime && entry.date.hour == hour)
            .map((entry) => entry.task)
            .toList(),
      ),
    );
  }
  final untimed = inRange
      .where((entry) => !entry.hasTime)
      .map((entry) => entry.task)
      .toList();
  if (untimed.isNotEmpty || result.isEmpty) {
    result.add(
      _StorySegment(
        title: 'Any time',
        subtitle: DateFormat('EEEE, MMMM d').format(branch.startDate),
        tasks: untimed,
      ),
    );
  }
  return result;
}

List<_StorySegment> _daySegments(
  PlanningStoryBranch branch,
  List<({TaskModel task, DateTime date, bool hasTime})> entries,
) {
  final result = <_StorySegment>[];
  var cursor = DateTime(
      branch.startDate.year, branch.startDate.month, branch.startDate.day);
  final end =
      DateTime(branch.endDate.year, branch.endDate.month, branch.endDate.day);
  while (!cursor.isAfter(end)) {
    final day = cursor;
    result.add(
      _StorySegment(
        title: DateFormat('EEEE').format(day),
        subtitle: DateFormat('MMMM d, yyyy').format(day),
        tasks: entries
            .where((entry) => _sameDate(entry.date, day))
            .map((entry) => entry.task)
            .toList(),
      ),
    );
    cursor = cursor.add(const Duration(days: 1));
  }
  return result;
}

List<_StorySegment> _weekSegments(
  PlanningStoryBranch branch,
  List<({TaskModel task, DateTime date, bool hasTime})> entries,
) {
  final result = <_StorySegment>[];
  var cursor = DateTime(
      branch.startDate.year, branch.startDate.month, branch.startDate.day);
  final end =
      DateTime(branch.endDate.year, branch.endDate.month, branch.endDate.day);
  var number = 1;
  while (!cursor.isAfter(end)) {
    final weekStart = cursor;
    final weekEnd = DateTime.fromMillisecondsSinceEpoch(
      math
          .min(
            cursor.add(const Duration(days: 6)).millisecondsSinceEpoch,
            end.millisecondsSinceEpoch,
          )
          .toInt(),
    );
    result.add(
      _StorySegment(
        title: 'Week $number',
        subtitle:
            '${DateFormat('MMM d').format(weekStart)} – ${DateFormat('MMM d').format(weekEnd)}',
        tasks: entries
            .where((entry) =>
                !_dateOnly(entry.date).isBefore(weekStart) &&
                !_dateOnly(entry.date).isAfter(weekEnd))
            .map((entry) => entry.task)
            .toList(),
      ),
    );
    cursor = cursor.add(const Duration(days: 7));
    number += 1;
  }
  return result;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDate(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
