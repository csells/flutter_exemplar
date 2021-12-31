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
  static const unreadyRouteNames = ['splash', 'login', 'loading'];

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

  Page<void> _page(GoRouterState state, Widget child) =>
      CustomTransitionPage<void>(
        key: state.pageKey,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        child: child,
      );

  late final router = GoRouter(
    debugLogDiagnostics: true,
    routerNeglect: true,
    routes: [
      GoRoute(
        name: 'splash',
        path: '/splash',
        pageBuilder: (context, state) => _page(state, const SplashPage()),
      ),
      GoRoute(
        name: 'login',
        path: '/login',
        pageBuilder: (context, state) => _page(state, const LoginPage()),
      ),
      GoRoute(
        name: 'loading',
        path: '/loading',
        pageBuilder: (context, state) => _page(state, const LoadingPage()),
      ),
      GoRoute(
        name: 'home',
        path: '/',
        pageBuilder: (context, state) => _page(state, const HomePage()),
      ),
      GoRoute(
        name: 'settings',
        path: '/settings',
        pageBuilder: (context, state) => _page(state, const SettingsPage()),
      ),
    ],
    refreshListenable: widget.appInfo,
    redirect: (state) {
      // grab the name of the redirect route
      String? redirName;
      switch (widget.appInfo.state) {
        // for the unready states, redirect to the corresponding routes
        case AppState.starting:
          redirName = 'splash';
          break;
        case AppState.loggedOut:
          redirName = 'login';
          break;
        case AppState.loading:
          redirName = 'loading';
          break;

        // for the ready state, redirect to the deep link or the home route as
        // appropriate; most commonly, there will be no deep link and we'll let
        // the route through w/o redirecting, e.g. going to the 'settings' route
        // after a successful login et al
        case AppState.ready:
          // if we've moved to the ready state but we're still on an unready
          // page, (splash, login or loading), check for a deep link param; if
          // there is one, leave `redirName` set to `null` as a signal to use
          // the deep link below; otherwise, we're done with the unready states
          // for now to redirect to home
          if (_unready(state) && state.queryParams['from'] == null) {
            redirName = 'home';
          }
          break;
      }

      // create the location based on the redirect route name
      String? location;
      if (redirName != null) {
        // pass along or capture the deep link in the location; if we're headed
        // to the home page (the default location), don't capture that as a
        // query param as it just messes up the link in the browser's address
        // bar; likewise, we never want to use one of the unready routes as a
        // deep link; in that case, we're passing along the existing query
        // params that have been captured previously (and may be empty);
        // otherwise, capture the deep link in the location for later use
        final homeloc = state.namedLocation('home');
        final queryParams = state.subloc == homeloc || _unready(state)
            ? state.queryParams
            : <String, String>{'from': state.subloc};
        location = state.namedLocation(redirName, queryParams: queryParams);
      } else {
        // use the deep link (which may be null, indicating no redirection)
        location = state.queryParams['from'];
      }

      // if we're already heading to the right place, return null; the location
      // itself may null at this point, indicating no redirection
      final redirect = location == state.location ? null : location;
      // debugPrint(
      //   '${widget.appInfo.state} redirect: ${state.location} => $redirect',
      // );
      return redirect;
    },
    errorPageBuilder: (context, state) =>
        _page(state, ErrorScreen(state.error)),
  );

  List<String>? unreadyRouteLocs;

  bool _unready(GoRouterState state) {
    unreadyRouteLocs ??= [
      // TODO: why does this work...
      for (final n in App.unreadyRouteNames) state.namedLocation(n)
      // ...but not this?
      // for (final n in App.unreadyRouteNames) router.namedLocation(n)
    ];
    return unreadyRouteLocs!.contains(state.subloc);
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(App.title)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              Text('welcome!'),
            ],
          ),
        ),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => AppScaffold(
        destinationName: 'home',
        body: const Center(
          child: Text('hello, world'),
        ),
      );
}

class LoginPage extends StatelessWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(App.title)),
        body: Center(
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
        ),
      );
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(App.title)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              Text('loading...'),
            ],
          ),
        ),
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => AppScaffold(
        destinationName: 'settings',
        body: Consumer<SettingsInfo>(
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
        ),
      );
}

class AppScaffold extends StatelessWidget {
  AppScaffold({
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
  Widget build(BuildContext context) => AdaptiveNavigationScaffold(
        selectedIndex: selectedIndex,
        destinations: destinations,
        appBar: AdaptiveAppBar(title: const Text(App.title)),
        fabInRail: false,
        body: body,
        navigationTypeResolver: (context) =>
            MediaQuery.of(context).size.width < 600
                ? NavigationType.rail
                : NavigationType.drawer,
        onDestinationSelected: (index) async {
          // TODO: close the drawer
          // some of these options don't navigate; the ones that do don't go
          // somewhere if they're already there

          switch (destinations[index].title.toLowerCase()) {
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
                applicationLegalese: 'Copyright © 2021, Acme, Corp.',
              );
              break;
            default:
              throw Exception(
                'Unknown destination: ${destinations[index].title}',
              );
          }
        },
      );
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
