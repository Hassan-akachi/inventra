import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_screen.dart';
import '../features/account/team_screen.dart';
import '../features/catalogue/categories_screen.dart';
import '../features/catalogue/item_detail_screen.dart';
import '../features/catalogue/item_edit_screen.dart';
import '../features/catalogue/items_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/expenses/expenses_screen.dart';
import '../features/home/home_screen.dart';
import '../features/reports/rates_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/reports/snapshots_screen.dart';
import '../features/inventory/alerts.dart';
import '../features/inventory/restock_screen.dart';
import '../features/inventory/restocks_screen.dart';
import '../features/inventory/stock_count_screen.dart';
import '../features/more/more_screen.dart';
import '../features/sales/cart_screen.dart';
import '../features/sales/sale_detail_screen.dart';
import '../features/sales/sales_history_screen.dart';
import '../features/sales/sell_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shops/shops_screen.dart';
import '../features/suppliers/suppliers_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _TabShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/sell', builder: (_, __) => const SellScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/items', builder: (_, __) => const ItemsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
          ]),
        ],
      ),
      // Full-screen pages (cover the bottom bar).
      GoRoute(
        path: '/item/new',
        builder: (_, state) =>
            ItemEditScreen(barcode: state.uri.queryParameters['barcode']),
      ),
      GoRoute(
        path: '/item/:id',
        builder: (_, state) =>
            ItemDetailScreen(itemId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/item/:id/edit',
        builder: (_, state) =>
            ItemEditScreen(itemId: state.pathParameters['id']),
      ),
      GoRoute(path: '/categories', builder: (_, __) => const CategoriesScreen()),
      GoRoute(path: '/shops', builder: (_, __) => const ShopsScreen()),
      GoRoute(path: '/suppliers', builder: (_, __) => const SuppliersScreen()),
      GoRoute(
          path: '/supplier/new',
          builder: (_, __) => const SupplierEditScreen()),
      GoRoute(
        path: '/supplier/:id',
        builder: (_, state) =>
            SupplierEditScreen(supplierId: state.pathParameters['id']),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
      GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
      GoRoute(
        path: '/restock',
        builder: (_, state) =>
            RestockScreen(itemId: state.uri.queryParameters['item']),
      ),
      GoRoute(path: '/restocks', builder: (_, __) => const RestocksScreen()),
      GoRoute(path: '/stock-count', builder: (_, __) => const StockCountScreen()),
      GoRoute(path: '/alerts', builder: (_, __) => const AlertsScreen()),
      GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
      GoRoute(path: '/team', builder: (_, __) => const TeamScreen()),
      GoRoute(path: '/rates', builder: (_, __) => const RatesScreen()),
      GoRoute(path: '/expenses', builder: (_, __) => const ExpensesScreen()),
      GoRoute(path: '/snapshots', builder: (_, __) => const SnapshotsScreen()),
      GoRoute(path: '/sales', builder: (_, __) => const SalesHistoryScreen()),
      GoRoute(
        path: '/sale/:id',
        builder: (_, state) => SaleDetailScreen(
          saleId: state.pathParameters['id']!,
          justCompleted: state.uri.queryParameters['done'] == '1',
        ),
      ),
      GoRoute(path: '/customers', builder: (_, __) => const CustomersScreen()),
      GoRoute(
          path: '/customer/new',
          builder: (_, __) => const CustomerEditScreen()),
      GoRoute(
        path: '/customer/:id',
        builder: (_, state) =>
            CustomerDetailScreen(customerId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/customer/:id/edit',
        builder: (_, state) =>
            CustomerEditScreen(customerId: state.pathParameters['id']),
      ),
    ],
  );
});

class _TabShell extends StatelessWidget {
  const _TabShell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.point_of_sale_outlined),
              selectedIcon: Icon(Icons.point_of_sale),
              label: 'Sell'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Items'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Reports'),
          NavigationDestination(
              icon: Icon(Icons.menu), selectedIcon: Icon(Icons.menu_open), label: 'More'),
        ],
      ),
    );
  }
}
