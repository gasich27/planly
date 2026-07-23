import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/plan_model.dart';
import '../core/models/dashboard_model.dart';
import '../core/models/story_branch_model.dart';
import '../core/services/api_service.dart';

class PlannerProvider extends ChangeNotifier {
  final ApiService _apiService;

  List<PlanModel> plans = <PlanModel>[];
  bool isLoading = false;
  String? error;
  PlanModel? selectedPlan;
  DashboardModel? dashboard;
  DashboardModel? goalsDashboard;
  bool isGoalsLoading = false;
  List<StoryBranchModel> storyBranches = <StoryBranchModel>[];
  String dashboardContext = 'today';
  Timer? _refreshTimer;
  late final Future<void> _storyBranchesReady;

  PlannerProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService() {
    _storyBranchesReady = _loadStoryBranches();
    loadPlans();
    _refreshTimer = Timer.periodic(const Duration(hours: 6), (_) {
      loadPlans();
    });
  }

  Future<void> _loadStoryBranches() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded =
        preferences.getStringList('planly_story_branches') ?? <String>[];
    final loaded = <StoryBranchModel>[];
    for (final item in encoded) {
      try {
        final value = jsonDecode(item);
        if (value is Map<String, dynamic>) {
          loaded.add(StoryBranchModel.fromJson(value));
        }
      } catch (_) {
        // Ignore a damaged local branch and keep the remaining branches.
      }
    }
    storyBranches = loaded;
    notifyListeners();
  }

  Future<void> saveStoryBranch(StoryBranchModel branch) async {
    await _storyBranchesReady;
    final index = storyBranches.indexWhere((item) => item.id == branch.id);
    if (index == -1) {
      storyBranches = <StoryBranchModel>[...storyBranches, branch];
    } else {
      final updated = <StoryBranchModel>[...storyBranches];
      updated[index] = branch;
      storyBranches = updated;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      'planly_story_branches',
      storyBranches.map((item) => jsonEncode(item.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> deleteStoryBranch(String id) async {
    await _storyBranchesReady;
    storyBranches = storyBranches.where((item) => item.id != id).toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      'planly_story_branches',
      storyBranches.map((item) => jsonEncode(item.toJson())).toList(),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _apiService.dispose();
    super.dispose();
  }

  Future<void> loadPlans() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      List<PlanModel> loadedPlans = <PlanModel>[];

      try {
        loadedPlans = await _apiService.getPlans();
      } on ApiException {
        loadedPlans = <PlanModel>[];
      }

      if (loadedPlans.isNotEmpty) {
        plans = loadedPlans;
      } else {
        try {
          plans = [await _apiService.getLatestPlan()];
        } on ApiException {
          plans = await _loadSeedPlans();
        }
      }

      if (plans.isEmpty) {
        error = 'Не удалось загрузить планы';
      }

      if (selectedPlan != null) {
        final refreshed = _findPlanById(selectedPlan!.id);
        if (refreshed != null) {
          selectedPlan = refreshed;
        }
      }
      try {
        dashboard = await _apiService.getDashboard(dashboardContext);
      } on ApiException {
        dashboard = null;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDashboard(String context) async {
    dashboardContext = context;
    error = null;
    notifyListeners();
    try {
      dashboard = await _apiService.getDashboard(context);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      notifyListeners();
    }
  }

  Future<void> createPlanFromText(
    String text, {
    String? period,
    DateTime? targetDate,
  }) async {
    final command = text.trim();
    if (command.isEmpty) {
      return;
    }
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await _apiService.generatePlan(
        command,
        period ?? dashboardContext,
        targetDate: targetDate,
      );
      await loadPlans();
    } on ApiException catch (e) {
      error = e.message;
      rethrow;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadGoalsDashboard(DateTime date) async {
    isGoalsLoading = true;
    error = null;
    notifyListeners();
    try {
      goalsDashboard = await _apiService.getDashboard('today', date: date);
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      isGoalsLoading = false;
      notifyListeners();
    }
  }

  Future<String> transcribeAudio(File audio) async {
    error = null;
    try {
      return await _apiService.transcribeAudio(audio);
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      rethrow;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<List<PlanModel>> _loadSeedPlans() async {
    try {
      final raw = await rootBundle.loadString('assets/data/plan_seed.json');
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(PlanModel.fromJson)
            .toList();
      }
    } catch (_) {
      // Intentionally fall through to an empty list.
    }
    return <PlanModel>[];
  }

  Future<void> createPlanFromAudio(File audio, {DateTime? targetDate}) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final transcript = await _apiService.transcribeAudio(audio);
      final plan = await _apiService.generatePlan(
        transcript,
        'day',
        targetDate: targetDate ?? DateTime.now(),
      );
      await loadPlans();
      selectedPlan = _findPlanById(plan.id) ?? plan;
      if (!plans.any((item) => item.id == plan.id)) {
        plans = <PlanModel>[plan, ...plans];
      }
    } on ApiException catch (e) {
      error = e.message;
      rethrow;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleTaskStatus(
      int planId, int taskId, String newStatus) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await _apiService.updateTaskStatus(planId, taskId, newStatus);
      await loadPlans();
      if (selectedPlan?.id == planId) {
        selectedPlan = _findPlanById(planId);
      }
    } on ApiException catch (e) {
      error = e.message;
      rethrow;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> aiEditPlan(int planId, String instruction) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await _apiService.aiEditPlan(planId, instruction);
      await loadPlans();
    } on ApiException catch (e) {
      error = e.message;
      rethrow;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<File> exportPlan(int planId) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      return await _apiService.exportIcs(planId);
    } on ApiException catch (e) {
      error = e.message;
      rethrow;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void setSelectedPlan(PlanModel? plan) {
    selectedPlan = plan;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  PlanModel? _findPlanById(int id) {
    for (final plan in plans) {
      if (plan.id == id) {
        return plan;
      }
    }
    return null;
  }

  PlanModel? planById(int id) {
    return _findPlanById(id);
  }

  void updateLocalPlanTaskStatus(int planId, int taskId, String status) {
    final updatedPlans = plans.map((plan) {
      if (plan.id != planId) {
        return plan;
      }
      final updatedTasks = plan.structuredPlan.map((task) {
        if (task.id != taskId) {
          return task;
        }
        return task.copyWith(status: status);
      }).toList();
      return plan.copyWith(structuredPlan: updatedTasks);
    }).toList();
    plans = updatedPlans;
    if (selectedPlan?.id == planId) {
      selectedPlan = _findPlanById(planId);
    }
    notifyListeners();
  }
}
