import 'package:enterprise_pos/api/customer_area_service.dart';
import 'package:enterprise_pos/api/sale_source_service.dart';
import 'package:enterprise_pos/services/catalog_cache_service.dart';
import 'package:enterprise_pos/widgets/app_feedback.dart';
import 'package:enterprise_pos/widgets/reference_data_manager_dialog.dart';
import 'package:enterprise_pos/widgets/sale_source_manager_dialog.dart';
import 'package:flutter/material.dart';

class SaleReferenceDataService {
  static int? _metaInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool isSourceActive(Map<String, dynamic> source) {
    final value = source['is_active'];
    return value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == 'true';
  }

  static bool isSourceDefault(Map<String, dynamic> source) {
    final value = source['is_default'];
    return value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == 'true';
  }

  static bool isAreaActive(Map<String, dynamic> area) {
    final value = area['is_active'];
    return value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == 'true';
  }

  static Map<String, dynamic>? findSourceById(
    List<Map<String, dynamic>> sources,
    int? id,
  ) {
    if (id == null) return null;
    for (final s in sources) {
      if (_metaInt(s['id']) == id) return s;
    }
    return null;
  }

  static Map<String, dynamic>? findAreaById(
    List<Map<String, dynamic>> areas,
    int? id,
  ) {
    if (id == null) return null;
    for (final a in areas) {
      if (_metaInt(a['id']) == id) return a;
    }
    return null;
  }

  static String? areaNameById(
    List<Map<String, dynamic>> areas,
    int? id,
  ) {
    final name = (findAreaById(areas, id)?['name'] ?? '').toString().trim();
    return name.isEmpty ? null : name;
  }

  static Future<({List<Map<String, dynamic>> sources, int? selectedId})>
      loadSaleSources({
    required SaleSourceService service,
    required int? branchId,
    required int? currentSelectedId,
    required bool isEditing,
    bool preferCache = false,
  }) async {
    if (branchId == null) {
      return (
        sources: const <Map<String, dynamic>>[],
        selectedId: isEditing ? currentSelectedId : null,
      );
    }

    List<Map<String, dynamic>> sources = const [];
    if (!preferCache) {
      try {
        sources = await service.getSaleSources();
      } catch (_) {}
    }
    if (sources.isEmpty) {
      try {
        sources =
            await CatalogCacheService.instance.saleSources(branchId: branchId);
      } catch (_) {}
    }

    if (sources.isEmpty) {
      return (
        sources: const <Map<String, dynamic>>[],
        selectedId: currentSelectedId,
      );
    }

    final sorted = sources.toList(growable: false)
      ..sort((a, b) {
        final ao = int.tryParse(a['sort_order']?.toString() ?? '') ?? 0;
        final bo = int.tryParse(b['sort_order']?.toString() ?? '') ?? 0;
        if (ao != bo) return ao.compareTo(bo);
        return (a['name'] ?? '').toString().toLowerCase().compareTo(
              (b['name'] ?? '').toString().toLowerCase(),
            );
      });

    int? next = currentSelectedId;
    final validCurrent =
        next != null && sorted.any((e) => _metaInt(e['id']) == next);
    if (!validCurrent && !isEditing) {
      final counter =
          sorted.where((e) => isSourceDefault(e) && isSourceActive(e)).toList();
      final active = sorted.where(isSourceActive).toList();
      next = _metaInt(
        (counter.isNotEmpty
            ? counter.first
            : (active.isNotEmpty
                ? active.first
                : const <String, dynamic>{}))['id'],
      );
    }

    return (sources: sorted, selectedId: next ?? currentSelectedId);
  }

  static Future<({List<Map<String, dynamic>> areas, int? selectedId})>
      loadCustomerAreas({
    required CustomerAreaService service,
    required int? branchId,
    required int? currentSelectedId,
    required bool isEditing,
    bool preferCache = false,
  }) async {
    if (branchId == null) {
      return (
        areas: const <Map<String, dynamic>>[],
        selectedId: isEditing ? currentSelectedId : null,
      );
    }

    List<Map<String, dynamic>> areas = const [];
    if (!preferCache) {
      try {
        areas = await service.getAreas(activeOnly: true);
      } catch (_) {}
    }
    if (areas.isEmpty) {
      try {
        areas = await CatalogCacheService.instance.customerAreas(
          branchId: branchId,
          activeOnly: true,
        );
      } catch (_) {}
    }

    final sorted = areas.toList(growable: false)
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));

    final currentStillAvailable = currentSelectedId == null ||
        sorted.any((area) => _metaInt(area['id']) == currentSelectedId);
    final nextId =
        (!isEditing && !currentStillAvailable) ? null : currentSelectedId;

    return (areas: sorted, selectedId: nextId);
  }

  static Future<int?> manageSaleSources({
    required BuildContext context,
    required SaleSourceService service,
    required int? selectedId,
    required String? effectiveBranchId,
    required String token,
    required Future<void> Function({bool preferCache}) onReload,
  }) async {
    final result = await showSaleSourceManagerDialog(
      context: context,
      service: service,
      selectedId: selectedId,
    );
    if (!context.mounted || result == null) return null;
    await onReload();
    if (result.changed) {
      final branchId = int.tryParse(effectiveBranchId ?? '');
      CatalogCacheService.instance
          .refresh(token: token, branchId: branchId, force: true)
          .then((_) => onReload(preferCache: true));
    }
    return result.selectedId;
  }

  static Future<int?> manageCustomerAreas({
    required BuildContext context,
    required CustomerAreaService service,
    required int? selectedId,
    required String? effectiveBranchId,
    required String token,
    required bool hasPermission,
    required Future<void> Function({bool preferCache}) onReload,
  }) async {
    if (!hasPermission) {
      AppFeedback.warning(
        context,
        'You do not have permission to manage customer town / area values.',
      );
      return null;
    }
    final result = await showNamedReferenceManagerDialog(
      context: context,
      title: 'Town / Areas',
      singularLabel: 'Town / Area',
      icon: Icons.location_city_outlined,
      selectedId: selectedId,
      loadItems: () => service.getAreas(activeOnly: true),
      createItem: service.createArea,
      updateItem: service.updateArea,
      subtitle: 'Create, rename, or choose an area without leaving the sale.',
      selectedSubtitle: 'Selected for this sale',
    );
    if (!context.mounted || result == null) return null;
    await onReload();
    if (result.changed) {
      final branchId = int.tryParse(effectiveBranchId ?? '');
      CatalogCacheService.instance
          .refresh(token: token, branchId: branchId, force: true)
          .then((_) => onReload(preferCache: true));
    }
    return result.selectedId;
  }
}
