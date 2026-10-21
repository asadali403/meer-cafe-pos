import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../services/sync_service.dart';
import '../widgets/common.dart';
import 'billing/billing_screen.dart';
import 'billing/bills_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'login/change_password_screen.dart';
import 'products/products_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/backup_screen.dart';
import 'settings/settings_screen.dart';
import 'settings/sync_screen.dart';
import 'settings/users_screen.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final bool adminOnly;
  final Widget Function() build;
  const _NavItem(this.label, this.icon, this.build, {this.adminOnly = false});
}

/// Main window after sign-in: sidebar navigation filtered by role.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _reload = 0;

  static final _all = <_NavItem>[
    _NavItem(
      'Dashboard',
      Icons.space_dashboard_outlined,
      () => const DashboardScreen(),
      adminOnly: true,
    ),
    _NavItem('Billing', Icons.point_of_sale, () => const BillingScreen()),
    _NavItem('Bills', Icons.receipt_long_outlined, () => const BillsScreen()),
    _NavItem(
      'Products',
      Icons.coffee_outlined,
      () => const ProductsScreen(),
      adminOnly: true,
    ),
    _NavItem(
      'Reports',
      Icons.insights_outlined,
      () => const ReportsScreen(),
      adminOnly: true,
    ),
    _NavItem(
      'Sync',
      Icons.cloud_sync_outlined,
      () => const SyncScreen(),
      adminOnly: true,
    ),
    _NavItem(
      'Users',
      Icons.group_outlined,
      () => const UsersScreen(),
      adminOnly: true,
    ),
    _NavItem(
      'Settings',
      Icons.settings_outlined,
      () => const SettingsScreen(),
      adminOnly: true,
    ),
    _NavItem(
      'Backup',
      Icons.backup_outlined,
      () => const BackupScreen(),
      adminOnly: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final user = app.user!;
    final items = _all.where((i) => !i.adminOnly || user.isAdmin).toList();
    if (_index >= items.length) _index = 0;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 236,
            color: MeerColors.black,
            child: Column(
              children: [
                const SizedBox(height: 22),
                if (user.isAdmin)
                  Tooltip(
                    message: 'View users and login information',
                    child: InkWell(
                      onTap: () => setState(() {
                        final usersIndex = items.indexWhere(
                          (item) => item.label == 'Users',
                        );
                        if (_index == usersIndex) _reload++;
                        _index = usersIndex;
                      }),
                      child: const MeerLogo(size: 92),
                    ),
                  )
                else
                  const MeerLogo(size: 92),
                const SizedBox(height: 8),
                Text(
                  app.settings.cafeName,
                  style: const TextStyle(
                    color: MeerColors.gold,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'Point of Sale',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _SideButton(
                          item: items[i],
                          selected: i == _index,
                          onTap: () => setState(() {
                            if (_index == i) _reload++;
                            _index = i;
                          }),
                        ),
                    ],
                  ),
                ),
                if (app.sync != null)
                  _SyncIndicator(
                    sync: app.sync!,
                    onTap: user.isAdmin
                        ? () => setState(
                            () => _index = items.indexWhere(
                              (e) => e.label == 'Sync',
                            ),
                          )
                        : null,
                  ),
                const Divider(color: Colors.white12, height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: MeerColors.gold,
                        foregroundColor: MeerColors.black,
                        child: Text(
                          user.displayName.isEmpty
                              ? '?'
                              : user.displayName[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              user.role.label,
                              style: const TextStyle(
                                color: MeerColors.goldLight,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white70,
                        ),
                        tooltip: 'Account',
                        onSelected: (v) async {
                          if (v == 'password') {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChangePasswordScreen(),
                              ),
                            );
                          } else if (v == 'logout') {
                            app.signOut();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'password',
                            child: Text('Change password'),
                          ),
                          PopupMenuItem(
                            value: 'logout',
                            child: Text('Sign out'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('${items[_index].label}-$_reload'),
              child: items[_index].build(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _SideButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? MeerColors.gold : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          hoverColor: Colors.white10,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: selected ? MeerColors.black : Colors.white70,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Text(
                  item.label,
                  style: TextStyle(
                    color: selected ? MeerColors.black : Colors.white,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 15,
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

class _SyncIndicator extends StatelessWidget {
  final SyncService sync;
  final VoidCallback? onTap;
  const _SyncIndicator({required this.sync, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final c = sync.counts;
        final (icon, color, text) = sync.running
            ? (Icons.sync, MeerColors.goldLight, 'Syncing...')
            : c.failed > 0
            ? (
                Icons.cloud_off,
                const Color(0xFFFF8A80),
                '${c.failed + c.pending} waiting to sync',
              )
            : c.pending > 0
            ? (
                Icons.cloud_upload_outlined,
                MeerColors.goldLight,
                '${c.pending} pending sync',
              )
            : (
                Icons.cloud_done_outlined,
                const Color(0xFF81C784),
                'All synced',
              );
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
