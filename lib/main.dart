import 'package:adaptive_navigation/adaptive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  // load and initialize settings, which is needed to create the app
  final settings = await SettingsInfo.load();
  runApp(App(settings));
}

class LoginInfo extends ChangeNotifier {
  String? _userName;

  String? get userName => _userName;
  bool get loggedIn => _userName != null;

  Future<void> login(String userName) async {
    _userName = userName;
    notifyListeners();

    // login
    await Future<void>.delayed(const Duration(seconds: 2)); // TODO
  }

  Future<void> logout() async {
    _userName = null;
    notifyListeners();

    // logout
    await Future<void>.delayed(const Duration(seconds: 2)); // TODO
  }
}

class Repository {
  Repository._();

  static Future<Repository?> get(String userName) async {
    // load the repository for the user
    await Future<void>.delayed(const Duration(seconds: 2)); // TODO

    return Repository._();
  }
}

enum AppState { starting, loggedOut, loading, ready }

class AppInfo extends ChangeNotifier {
  AppInfo() {
    loginInfo.addListener(_loginChange);
    repo.addListener(notifyListeners);
    _start();
  }

  final loginInfo = LoginInfo();
  final repo = ValueNotifier<Repository?>(null);
  var _state = AppState.starting;
  static const _minSplashDuration = Duration(seconds: 2);

  AppState get state => _state;

  Future<void> _loginChange() async {
    if (!loginInfo.loggedIn) {
      _state = AppState.loggedOut;
      repo.value = null; // calls notifyListeners
      return;
    }

    // let listeners know we're loading
    _state = AppState.loading;
    notifyListeners();

    // get a repository for the user
    final repoVal = await Repository.get(loginInfo.userName!);
    if (repoVal != null) {
      // we're ready
      _state = AppState.ready;
    } else {
      // if loading the repo failed, log the user out
      await loginInfo.logout();
    }

    repo.value = repoVal; // calls notifyListeners
  }

  Future<void> _start() async {
    assert(_state == AppState.starting);

    // start the app
    await Future.wait([
      Future<void>.delayed(_minSplashDuration),
      Future<void>.delayed(const Duration(seconds: 1)), // TODO
    ]);

    _state = AppState.loggedOut;
    notifyListeners();
  }

  @override
  void dispose() {
    loginInfo.removeListener(_loginChange);
    repo.removeListener(notifyListeners);
    super.dispose();
  }
}

class SettingsInfo with ChangeNotifier {
  SettingsInfo._(this.prefs) {
    // load the initial settings
    final themeModeName = prefs.getString('themeMode');
    _themeMode = ThemeMode.values
        .asNameMap()
        .entries
        .singleWhere(
          (e) => e.key == themeModeName,
          orElse: () => const MapEntry('system', ThemeMode.system),
        )
        .value;
  }

  static Future<SettingsInfo> load() async =>
      SettingsInfo._(await SharedPreferences.getInstance());

  late ThemeMode _themeMode;
  final SharedPreferences prefs;

  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode? newThemeMode) async {
    if (newThemeMode == null) return;
    if (newThemeMode == _themeMode) return;

    _themeMode = newThemeMode;
    notifyListeners();
    await prefs.setString('themeMode', newThemeMode.name);
  }
}

class App extends StatefulWidget {
  App(this.settings, {Key? key}) : super(key: key);

  static const title = 'Flutter App';
  static const unreadyStateRoutes = <AppState, String>{
    AppState.starting: 'splash',
    AppState.loggedOut: 'login',
    AppState.loading: 'loading',
  };

  final appInfo = AppInfo();
  final SettingsInfo settings;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: widget.appInfo),
          ChangeNotifierProvider.value(value: widget.settings),
        ],
        child: Consumer<SettingsInfo>(
          builder: (context, settings, child) => MaterialApp.router(
            title: App.title,
            routerDelegate: router.routerDelegate,
            routeInformationParser: router.routeInformationParser,
            theme: ThemeData(),
            darkTheme: ThemeData.dark(),
            themeMode: settings.themeMode,
          ),
        ),
      );

  late final router = GoRouter(
    debugLogDiagnostics: true,
    routerNeglect: true,
    routes: [
      GoRoute(
        name: 'splash',
        path: '/splash',
        builder: (context, state) => _build(const SplashView()),
      ),
      GoRoute(
        name: 'login',
        path: '/login',
        builder: (context, state) => _build(const LoginView()),
      ),
      GoRoute(
        name: 'loading',
        path: '/loading',
        builder: (context, state) => _build(const LoadingView()),
      ),
      GoRoute(
        name: 'home',
        path: '/',
        builder: (context, state) => _build(const HomeView()),
      ),
      GoRoute(
        name: 'settings',
        path: '/settings',
        builder: (context, state) => _build(const SettingsView()),
      ),
    ],
    refreshListenable: widget.appInfo,
    redirect: (state) {
      final homeloc = state.namedLocation('home');

      // create the location based on the app state
      String? location;
      switch (widget.appInfo.state) {
        case AppState.starting:
        case AppState.loggedOut:
        case AppState.loading:
          assert(App.unreadyStateRoutes.containsKey(widget.appInfo.state));
          final redirName = App.unreadyStateRoutes[widget.appInfo.state]!;

          // for an unready state, redirect to the corresponding route,
          // passing along or capturing the deep link in the location; if we're
          // headed to the home page (the default location), don't capture that
          // as a query param as it just messes up the link in the browser's
          // address bar; likewise, we never want to use one of the unready
          // routes as a deep link; in that case, we're passing along the
          // existing query params that have been captured previously (and may
          // be empty); otherwise, capture the deep link in the location for
          // later use
          final queryParams = state.subloc == homeloc || _unready(state)
              ? state.queryParams
              : <String, String>{'from': state.subloc};
          location = state.namedLocation(redirName, queryParams: queryParams);
          break;

        case AppState.ready:
          // if we've moved to the ready state but we're still on an unready
          // page, (splash, login or loading), use a deep link if there is
          // one; otherwise, redirect to the home page
          if (_unready(state)) location = state.queryParams['from'] ?? homeloc;
          break;
      }

      // if we're already heading to the right place, return null; the location
      // itself may null at this point, indicating no redirection
      return location == state.location ? null : location;
    },
    errorBuilder: (context, state) => _build(ErrorScreen(state.error)),
    navigatorBuilder: (context, state, child) {
      final routes = router.routerDelegate.routes.where(
        (r) =>
            state.subloc == '/' && state.subloc == r.path ||
            r.path != '/' && state.subloc.startsWith(r.path),
      );

      assert(
        routes.length == 1,
        'no single top-level route for ${state.subloc}',
      );

      // use the navigatorBuilder to keep the SharedScaffold from being animated
      // as new pages as shown; wrap that in single-page Navigator at the root
      // provides an Overlay needed for the adaptive navigation scaffold and a
      // root Navigator to show the About box
      return Navigator(
        onPopPage: (route, result) {
          route.didPop(result);
          return false;
        },
        pages: [
          MaterialPage<void>(
            child: _unready(state)
                ? UnreadyScaffold(body: child)
                : ReadyScaffold(
                    destinationName: routes.first.name!,
                    body: child,
                  ),
          ),
        ],
      );
    },
  );

  // wrap the view widgets in a Scaffold to get the exit animation just right on
  // the page being replaced
  Widget _build(Widget child) => Scaffold(body: child);

  List<String>? unreadyRouteLocs;
  bool _unready(GoRouterState state) {
    // cache the unready route locations the first time we're called
    unreadyRouteLocs ??= [
      for (final n in App.unreadyStateRoutes.values) state.namedLocation(n)
    ];
    return unreadyRouteLocs!.contains(state.subloc);
  }
}

class SplashView extends StatelessWidget {
  const SplashView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            Text('welcome!'),
          ],
        ),
      );
}

class HomeView extends StatelessWidget {
  const HomeView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => const Center(
        child: Text('hello, world'),
      );
}

class LoginView extends StatelessWidget {
  const LoginView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () =>
                  context.read<AppInfo>().loginInfo.login('test-user'),
              child: const Text('Login'),
            ),
          ],
        ),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            Text('loading...'),
          ],
        ),
      );
}

class SettingsView extends StatelessWidget {
  const SettingsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Consumer<SettingsInfo>(
        builder: (context, settings, child) => Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButton<ThemeMode>(
            value: settings.themeMode,
            onChanged: settings.setThemeMode,
            items: const [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text('System Theme'),
              ),
              DropdownMenuItem(
                value: ThemeMode.light,
                child: Text('Light Theme'),
              ),
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Text('Dark Theme'),
              )
            ],
          ),
        ),
      );
}

class UnreadyScaffold extends StatelessWidget {
  const UnreadyScaffold({
    required this.body,
    Key? key,
  }) : super(key: key);

  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(App.title)),
        body: body,
      );
}

class ReadyScaffold extends StatefulWidget {
  ReadyScaffold({
    required String destinationName,
    required this.body,
    Key? key,
  })  : selectedIndex = destinations
            .indexWhere((d) => d.title.toLowerCase() == destinationName),
        super(key: key) {
    if (selectedIndex == -1) {
      throw Exception('destinationName not found: $destinationName');
    }
  }

  static const destinations = [
    AdaptiveScaffoldDestination(title: 'Home', icon: Icons.home),
    AdaptiveScaffoldDestination(title: 'Settings', icon: Icons.settings),
    AdaptiveScaffoldDestination(title: 'About', icon: Icons.info),
    AdaptiveScaffoldDestination(title: 'Logout', icon: Icons.logout),
  ];

  final Widget body;
  final int selectedIndex;

  @override
  State<ReadyScaffold> createState() => _ReadyScaffoldState();
}

class _ReadyScaffoldState extends State<ReadyScaffold> {
  @override
  Widget build(BuildContext context) => AdaptiveNavigationScaffold(
        selectedIndex: widget.selectedIndex,
        destinations: ReadyScaffold.destinations,
        appBar: AdaptiveAppBar(title: const Text(App.title)),
        fabInRail: false,
        body: widget.body,
        navigationTypeResolver: (context) =>
            _drawerSize ? NavigationType.drawer : NavigationType.bottom,
        onDestinationSelected: (index) async {
          // if there's a drawer, close it
          if (_drawerSize) Navigator.pop(context);

          switch (ReadyScaffold.destinations[index].title.toLowerCase()) {
            case 'home':
              context.goNamed('home');
              break;
            case 'logout':
              context.read<AppInfo>().loginInfo.logout();
              context.goNamed('home'); // clear query string
              break;
            case 'settings':
              context.goNamed('settings');
              break;
            case 'about':
              final packageInfo = await PackageInfo.fromPlatform();
              showAboutDialog(
                context: context,
                applicationName: packageInfo.appName,
                applicationVersion: 'v${packageInfo.version}',
                applicationLegalese: 'Copyright © 2022, Acme, Corp.',
              );
              break;
            default:
              throw Exception(
                'Unhandled destination: '
                '${ReadyScaffold.destinations[index].title.toLowerCase()}',
              );
          }
        },
      );

  bool get _drawerSize => MediaQuery.of(context).size.width >= 600;
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen(this.error, {Key? key}) : super(key: key);
  final Exception? error;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Page Not Found')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SelectableText(error?.toString() ?? 'page not found'),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Home'),
              ),
            ],
          ),
        ),
      );
}
