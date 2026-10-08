import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/book_opening.dart';
import '../features/book_details/presentation/book_details_screen.dart';
import '../features/friends/presentation/account_screen.dart';
import '../features/friends/presentation/friend_shelf_screen.dart';
import '../features/friends/presentation/friends_screen.dart';
import '../features/history/presentation/journal_screen.dart';
import '../features/library/presentation/book_form.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/reading/presentation/reading_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/sharing/presentation/share_app_button.dart';
import '../features/sync/presentation/conflict_dialog.dart';
import '../features/sync/presentation/sync_controller.dart';
import '../features/sync/presentation/welcome_screen.dart';
import '../features/updates/update_controller.dart';
import '../features/updates/update_widgets.dart';
import 'providers.dart';

class ReadingLibraryApp extends ConsumerStatefulWidget {
  const ReadingLibraryApp({super.key});
  @override
  ConsumerState<ReadingLibraryApp> createState() => _ReadingLibraryAppState();
}

class _ReadingLibraryAppState extends ConsumerState<ReadingLibraryApp>
    with WidgetsBindingObserver {
  // Tells the router to look again when the sign-in state changes.
  final _signInChanged = ValueNotifier(0);

  /// With accounts required, nothing opens until someone is signed in. The
  /// answer comes from the device, so it is immediate and works offline.
  String? _gate(GoRouterState state) {
    if (!ref.read(accountRequiredProvider) || ref.read(demoProvider)) {
      return null;
    }
    final signedIn = ref.read(signedInProvider).value;
    final at = state.uri.path;
    if (signedIn == null) return at == '/loading' ? null : '/loading';
    if (!signedIn) return at == '/welcome' ? null : '/welcome';
    return at == '/welcome' || at == '/loading' ? '/library' : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(updateControllerProvider.notifier).check(automatic: true),
        );
      }
    });
    ref.listenManual(signedInProvider, (_, next) {
      _signInChanged.value++;
      if (next.value == true) {
        unawaited(ref.read(syncControllerProvider.notifier).sync());
      }
    }, fireImmediately: true);
    // A library on the phone and one on the account that cannot be combined:
    // the reader decides which to keep, wherever they are in the app.
    ref.listenManual(syncControllerProvider, (previous, next) {
      if (next.phase != SyncPhase.conflict ||
          previous?.phase == SyncPhase.conflict ||
          next.conflict == null) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _navigatorKey.currentState?.overlay?.context;
        if (mounted && context != null && context.mounted) {
          unawaited(showSyncConflict(context, ref, next.conflict!));
        }
      });
    }, fireImmediately: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(updateControllerProvider.notifier).check(automatic: true),
      );
      unawaited(ref.read(syncControllerProvider.notifier).sync());
    }
  }

  final _navigatorKey = GlobalKey<NavigatorState>();

  late final router = GoRouter(
    navigatorKey: _navigatorKey,
    initialLocation: '/library',
    refreshListenable: _signInChanged,
    redirect: (context, state) => _gate(state),
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
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
        builder: (_, state) {
          final q = state.uri.queryParameters;
          final hasPrefill = ['title', 'author', 'series'].any(q.containsKey);
          return BookForm(
            historical: q['past'] == 'true',
            prefill: hasPrefill
                ? BookPrefill(
                    title: q['title'],
                    author: q['author'],
                    seriesName: q['series'],
                    seriesNumber: int.tryParse(q['number'] ?? ''),
                  )
                : null,
          );
        },
      ),
      GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
      GoRoute(
        path: '/book/:id',
        // From the shelf the book opens like a real one; from anywhere else
        // the page rises softly.
        pageBuilder: (_, state) {
          final id = state.pathParameters['id']!;
          final extra = state.extra;
          final opening = extra is BookOpening && extra.book.id == id
              ? extra
              : null;
          return CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: Duration(
              milliseconds: opening == null ? 420 : 800,
            ),
            reverseTransitionDuration: Duration(
              milliseconds: opening == null ? 320 : 520,
            ),
            child: BookDetailsScreen(id: id),
            transitionsBuilder: (context, animation, _, child) {
              if (MediaQuery.disableAnimationsOf(context)) return child;
              if (opening != null) {
                return bookOpeningTransition(
                  context,
                  animation,
                  opening,
                  child,
                );
              }
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, .04),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
          );
        },
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
      GoRoute(path: '/friends', builder: (_, _) => const FriendsScreen()),
      GoRoute(
        path: '/friends/:id',
        builder: (_, state) => FriendShelfScreen(
          id: state.pathParameters['id']!,
          name: state.uri.queryParameters['name'] ?? 'Friend',
        ),
      ),
    ],
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.dispose();
    _signInChanged.dispose();
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
  Widget build(BuildContext context, WidgetRef ref) => _scaffold(context, ref);

  Widget _scaffold(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 56,
      title: Row(
        children: [
          const Icon(Icons.auto_stories_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ref.watch(demoProvider) ? 'READING ROOM · DEMO' : 'READING ROOM',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
      actions: [
        const ShareAppButton(iconOnly: true),
        IconButton(
          tooltip: 'Settings and backups',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.tune),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: Column(
        children: [
          const UpdateNotice(),
          Expanded(child: child),
        ],
      ),
    ),
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
