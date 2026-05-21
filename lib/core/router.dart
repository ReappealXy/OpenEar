import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/detail/detail_page.dart';
import '../features/home/home_page.dart';
import '../features/recorder/recorder_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomePage(),
        routes: [
          GoRoute(
            path: 'recorder',
            name: 'recorder',
            builder: (context, state) => const RecorderPage(),
          ),
          GoRoute(
            path: 'detail/:id',
            name: 'detail',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return DetailPage(recordingId: id);
            },
          ),
          GoRoute(
            path: 'search',
            name: 'search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: 'settings',
            name: 'settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});
