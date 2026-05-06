import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models/plan_model.dart';
import '../core/services/api_service.dart';

class PlannerProvider extends ChangeNotifier {
  final ApiService _apiService;

  List<PlanModel> plans = <PlanModel>[];
  bool isLoading = false;
  String? error;
  PlanModel? selectedPlan;
  Timer? _refreshTimer;

  PlannerProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService() {
    loadPlans();
    _refreshTimer = Timer.periodic(const Duration(hours: 6), (_) {
      loadPlans();
    });
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
      plans = await _apiService.getPlans();
      if (selectedPlan != null) {
        final refreshed = _findPlanById(selectedPlan!.id);
        if (refreshed != null) {
          selectedPlan = refreshed;
        }
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createPlanFromAudio(File audio) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final transcript = await _apiService.transcribeAudio(audio);
      final plan = await _apiService.generatePlan(transcript, 'day');
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

  Future<void> toggleTaskStatus(int planId, int taskId, String newStatus) async {
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
