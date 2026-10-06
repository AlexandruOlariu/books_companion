import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/book_details/presentation/book_details_screen.dart';
import '../features/history/presentation/journal_screen.dart';
import '../features/library/presentation/book_form.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/reading/presentation/reading_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'providers.dart';

class ReadingLibraryApp extends StatefulWidget {
  const ReadingLibraryApp({super.key});
  @override
  State<ReadingLibraryApp> createState() => _ReadingLibraryAppState();
}

class _ReadingLibraryAppState extends State<ReadingLibraryApp> {
  late final router = GoRouter(
    initialLocation: '/library',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            _RoomShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/library', builder: (_, _) => const _Destination(0)),
          GoRoute(path: '/reading', builder: (_, _) => const _Destination(1)),
          GoRoute(
            path: '/journal',
            builder: (_, state) => _Destination(
              2,
              year: int.tryParse(state.uri.queryParameters['year'] ?? ''),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/add',
        builder: (_, state) =>
            BookForm(historical: state.uri.queryParameters['past'] == 'true'),
      ),
      GoRoute(
        path: '/book/:id',
        builder: (_, state) =>
            BookDetailsScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/edit/:id',
        builder: (_, state) => Consumer(
          builder: (context, ref, _) => ref
              .watch(libraryProvider)
              .when(
                loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const Scaffold(
                  body: Center(child: Text('Could not load the book.')),
                ),
                data: (data) {
                  final book = data.books
                      .where((b) => b.id == state.pathParameters['id'])
                      .firstOrNull;
                  return book == null
                      ? Scaffold(
                          appBar: AppBar(),
                          body: const Center(child: Text('Book not found.')),
                        )
                      : BookForm(book: book);
                },
              ),
        ),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Reading Library',
    debugShowCheckedModeBanner: false,
    theme: roomTheme(),
    routerConfig: router,
  );
}

class _RoomShell extends ConsumerWidget {
  final String path;
  final Widget child;
  const _RoomShell({required this.path, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 56,
      title: Row(
        children: [
          const Icon(Icons.auto_stories_outlined, size: 20),
          const SizedBox(width: 10),
          Text(
            ref.watch(demoProvider) ? 'READING ROOM · DEMO' : 'READING ROOM',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Settings and backups',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.tune),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: SafeArea(top: false, bottom: false, child: child),
    bottomNavigationBar: NavigationBar(
      selectedIndex: path == '/reading'
          ? 1
          : path == '/journal'
          ? 2
          : 0,
      onDestinationSelected: (i) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        context.go(['/library', '/reading', '/journal'][i]);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.shelves), label: 'Library'),
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          label: 'Reading',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          label: 'Journal',
        ),
      ],
    ),
  );
}

class _Destination extends ConsumerWidget {
  final int index;
  final int? year;
  const _Destination(this.index, {this.year});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(libraryProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Your library could not be opened.'),
              TextButton(
                onPressed: () => ref.invalidate(libraryProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: (data) => switch (index) {
          0 => LibraryScreen(data: data),
          1 => ReadingScreen(data: data),
          _ => JournalScreen(
            key: ValueKey(year),
            data: data,
            initialYear: year,
          ),
        },
      );
}
