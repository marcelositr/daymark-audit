import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/journal/presentation/backup_dialog.dart';
import '../features/journal/presentation/open_export_dialog.dart';
import '../l10n/app_localizations.dart';
import 'about_dialog.dart';
import 'app_section_scope.dart';
import 'appearance_dialog.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const int _backupAction = 6;
  static const int _exportAction = 7;
  static const int _appearanceAction = 8;
  static const int _aboutAction = 9;

  late final ValueNotifier<int> _currentSectionIndex;

  @override
  void initState() {
    super.initState();
    _currentSectionIndex = ValueNotifier<int>(
      widget.navigationShell.currentIndex,
    );
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int currentIndex = widget.navigationShell.currentIndex;
    if (_currentSectionIndex.value != currentIndex) {
      _currentSectionIndex.value = currentIndex;
    }
  }

  @override
  void dispose() {
    _currentSectionIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final StatefulNavigationShell navigationShell = widget.navigationShell;
    final int bottomSelectedIndex = navigationShell.currentIndex < 4
        ? navigationShell.currentIndex
        : 4;
    final List<NavigationDestination> bottomDestinations = [
      NavigationDestination(
        icon: const Icon(Icons.today_outlined),
        selectedIcon: const Icon(Icons.today),
        label: l10n.today,
      ),
      NavigationDestination(
        icon: const Icon(Icons.calendar_month_outlined),
        selectedIcon: const Icon(Icons.calendar_month),
        label: l10n.monthly,
      ),
      NavigationDestination(
        icon: const Icon(Icons.event_outlined),
        selectedIcon: const Icon(Icons.event),
        label: l10n.future,
      ),
      NavigationDestination(
        icon: const Icon(Icons.book_outlined),
        selectedIcon: const Icon(Icons.book),
        label: l10n.collections,
      ),
      NavigationDestination(
        icon: const Icon(Icons.more_horiz),
        label: l10n.more,
      ),
    ];

    return AppSectionScope(
      currentIndex: _currentSectionIndex,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: navigationShell.currentIndex,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: _goToBranch,
                    trailing: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => showBackupDialog(context),
                            tooltip: l10n.backup,
                            icon: const Icon(Icons.backup_outlined),
                          ),
                          IconButton(
                            onPressed: () => showOpenExportDialog(context),
                            tooltip: l10n.openExport,
                            icon: const Icon(Icons.file_download_outlined),
                          ),
                          IconButton(
                            onPressed: () => showAppearanceDialog(context),
                            tooltip: l10n.appearance,
                            icon: const Icon(Icons.palette_outlined),
                          ),
                          IconButton(
                            onPressed: () => showDaymarkAboutDialog(context),
                            tooltip: l10n.about,
                            icon: const Icon(Icons.info_outline),
                          ),
                        ],
                      ),
                    ),
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.today_outlined),
                        selectedIcon: const Icon(Icons.today),
                        label: Text(l10n.today),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.calendar_month_outlined),
                        selectedIcon: const Icon(Icons.calendar_month),
                        label: Text(l10n.monthly),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.event_outlined),
                        selectedIcon: const Icon(Icons.event),
                        label: Text(l10n.future),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.book_outlined),
                        selectedIcon: const Icon(Icons.book),
                        label: Text(l10n.collections),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.search),
                        label: Text(l10n.search),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.format_list_numbered),
                        label: Text(l10n.index),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: navigationShell),
                ],
              ),
            );
          }

          return Scaffold(
            body: navigationShell,
            bottomNavigationBar: NavigationBar(
              selectedIndex: bottomSelectedIndex,
              onDestinationSelected: (index) {
                if (index < 4) {
                  _goToBranch(index);
                  return;
                }
                _showMore(context, l10n);
              },
              destinations: bottomDestinations,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showMore(BuildContext context, AppLocalizations l10n) async {
    final int? action = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.format_list_numbered),
                title: Text(l10n.index),
                onTap: () => Navigator.of(sheetContext).pop(5),
              ),
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(l10n.search),
                onTap: () => Navigator.of(sheetContext).pop(4),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text(l10n.backup),
                onTap: () => Navigator.of(sheetContext).pop(_backupAction),
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: Text(l10n.openExport),
                onTap: () => Navigator.of(sheetContext).pop(_exportAction),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text(l10n.appearance),
                onTap: () => Navigator.of(sheetContext).pop(_appearanceAction),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.about),
                onTap: () => Navigator.of(sheetContext).pop(_aboutAction),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || !context.mounted || action == null) {
      return;
    }
    if (action == _backupAction) {
      await showBackupDialog(context);
      return;
    }
    if (action == _exportAction) {
      await showOpenExportDialog(context);
      return;
    }
    if (action == _appearanceAction) {
      await showAppearanceDialog(context);
      return;
    }
    if (action == _aboutAction) {
      await showDaymarkAboutDialog(context);
      return;
    }
    _goToBranch(action);
  }

  void _goToBranch(int index) {
    final StatefulNavigationShell navigationShell = widget.navigationShell;
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
    if (_currentSectionIndex.value != index) {
      _currentSectionIndex.value = index;
    }
  }
}
