import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jodeals/screens/auth/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Stub out package_info_plus
    PackageInfo.setMockInitialValues(
      appName: 'JoDeals',
      packageName: 'com.jodeals.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'buildSignature',
    );

    // Mock local_auth and flutter_secure_storage method channels
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (methodCall) async {
        if (methodCall.method == 'isDeviceSupported') return false;
        if (methodCall.method == 'canCheckBiometrics') return false;
        return null;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.itspace.biz/flutter_secure_storage'),
      (methodCall) async {
        if (methodCall.method == 'read') return null;
        if (methodCall.method == 'write') return null;
        if (methodCall.method == 'delete') return null;
        return null;
      },
    );
  });

  Widget createLoginScreenUnderTest({
    required String baseUrl,
    required Future<void> Function(String token) onLoginSuccess,
    required VoidCallback onCancel,
  }) {
    return MaterialApp(
      home: LoginScreen(
        baseUrl: baseUrl,
        onLoginSuccess: onLoginSuccess,
        onCancel: onCancel,
        googleSignInHandler: () async {},
      ),
    );
  }

  testWidgets('Verify Login Screen UI Components Render correctly (Arabic/English Toggle)', (WidgetTester tester) async {
    await tester.pumpWidget(createLoginScreenUnderTest(
      baseUrl: 'https://jodealz.online',
      onLoginSuccess: (_) async {},
      onCancel: () {},
    ));

    // Verify Arabic text by default (e.g. 'تسجيل الدخول', 'تذكرني', 'البريد الإلكتروني')
    expect(find.text('تسجيل الدخول'), findsAtLeastNWidgets(1));
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
    expect(find.text('كلمة المرور'), findsOneWidget);
    expect(find.text('تذكرني'), findsOneWidget);

    // Toggle to English
    final langToggle = find.byIcon(Icons.translate);
    expect(langToggle, findsOneWidget);
    await tester.tap(langToggle);
    await tester.pumpAndSettle();

    // Verify English text is displayed now
    expect(find.text('Sign In'), findsAtLeastNWidgets(1));
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Remember Me'), findsOneWidget);
  });

  testWidgets('Verify validation for empty inputs (Arabic)', (WidgetTester tester) async {
    await tester.pumpWidget(createLoginScreenUnderTest(
      baseUrl: 'https://jodealz.online',
      onLoginSuccess: (_) async {},
      onCancel: () {},
    ));

    // Find the elevated button for sign in
    final signInButton = find.widgetWithText(ElevatedButton, 'تسجيل الدخول');
    expect(signInButton, findsOneWidget);

    // Tap without entering credentials
    await tester.tap(signInButton);
    await tester.pumpAndSettle();

    // Verify validator messages
    expect(find.text('الرجاء إدخال البريد الإلكتروني'), findsOneWidget);
    expect(find.text('الرجاء إدخال كلمة المرور'), findsOneWidget);
  });

  testWidgets('Verify validation for empty inputs (English)', (WidgetTester tester) async {
    await tester.pumpWidget(createLoginScreenUnderTest(
      baseUrl: 'https://jodealz.online',
      onLoginSuccess: (_) async {},
      onCancel: () {},
    ));

    // Toggle to English
    await tester.tap(find.byIcon(Icons.translate));
    await tester.pumpAndSettle();

    // Tap without entering credentials
    final signInButton = find.widgetWithText(ElevatedButton, 'Sign In');
    await tester.tap(signInButton);
    await tester.pumpAndSettle();

    // Verify validator messages in English
    expect(find.text('Please enter email'), findsOneWidget);
    expect(find.text('Please enter password'), findsOneWidget);
  });

  testWidgets('Verify email format validation', (WidgetTester tester) async {
    await tester.pumpWidget(createLoginScreenUnderTest(
      baseUrl: 'https://jodealz.online',
      onLoginSuccess: (_) async {},
      onCancel: () {},
    ));

    // Toggle to English
    await tester.tap(find.byIcon(Icons.translate));
    await tester.pumpAndSettle();

    // Find email and password fields
    final emailField = find.byType(TextFormField).first;
    final passwordField = find.byType(TextFormField).last;

    // Enter invalid email format
    await tester.enterText(emailField, 'invalidemail');
    await tester.enterText(passwordField, 'mysecretpassword');
    await tester.pumpAndSettle();

    // Click Sign In
    final signInButton = find.widgetWithText(ElevatedButton, 'Sign In');
    await tester.tap(signInButton);
    await tester.pumpAndSettle();

    // Expect invalid email validation message
    expect(find.text('Please enter a valid email'), findsOneWidget);
    expect(find.text('Please enter password'), findsNothing);
  });

  testWidgets('Verify password masking/unmasking toggle', (WidgetTester tester) async {
    await tester.pumpWidget(createLoginScreenUnderTest(
      baseUrl: 'https://jodealz.online',
      onLoginSuccess: (_) async {},
      onCancel: () {},
    ));

    // Verify password text field is obscured initially
    final textFieldFinder = find.descendant(
      of: find.byType(TextFormField).last,
      matching: find.byType(TextField),
    );
    TextField textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.obscureText, isTrue);

    // Tap visibility toggle icon
    final visibilityToggle = find.byIcon(Icons.visibility_off);
    expect(visibilityToggle, findsOneWidget);
    await tester.tap(visibilityToggle);
    await tester.pumpAndSettle();

    // Verify password is now unmasked (obscureText = false)
    textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.obscureText, isFalse);
  });

  testWidgets('Verify guest session is logged out after successful login and session verification', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'jodeals_auth_token': 'mock_guest_token'});

    await HttpOverrides.runWithHttpOverrides(() async {
      await tester.pumpWidget(createLoginScreenUnderTest(
        baseUrl: 'https://jodealz.online',
        onLoginSuccess: (_) async {},
        onCancel: () {},
      ));

      // Toggle to English
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      // Enter email and password
      final emailField = find.byType(TextFormField).first;
      final passwordField = find.byType(TextFormField).last;
      await tester.enterText(emailField, 'test@user.com');
      await tester.enterText(passwordField, 'password123');
      await tester.pumpAndSettle();

      // Find the elevated button for sign in
      final signInButton = find.widgetWithText(ElevatedButton, 'Sign In');
      await tester.tap(signInButton);
      
      // Pump to process async tasks (HTTP request and validation check)
      await tester.pump(const Duration(seconds: 2));

      // SharedPreferences should have been cleared of the mock guest token
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jodeals_auth_token'), isNull);
    }, MockHttpOverrides());
  });
}

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient();
  }
}

class MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => MockHttpClientRequest(url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => MockHttpClientRequest(url);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => MockHttpClientRequest(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockHttpClientRequest implements HttpClientRequest {
  final Uri url;
  MockHttpClientRequest(this.url);

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain();
  }

  @override
  Future<HttpClientResponse> close() async {
    if (url.path.contains('login.php')) {
      return MockHttpClientResponse(
        statusCode: 200,
        body: '{"status": "success", "token": "new_user_token"}',
      );
    } else if (url.path.contains('profile.php')) {
      return MockHttpClientResponse(
        statusCode: 200,
        body: '{"status": "success"}',
      );
    } else if (url.path.contains('logout.php')) {
      return MockHttpClientResponse(
        statusCode: 200,
        body: '{"status": "success"}',
      );
    }
    return MockHttpClientResponse(
      statusCode: 404,
      body: '{"status": "error", "message": "Not Found"}',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    debugPrint('MockHttpClientRequest: missing method called: ${invocation.memberName}');
    if (invocation.memberName == #done) {
      return Future<void>.value();
    }
    if (invocation.memberName == #flush) {
      return Future<void>.value();
    }
    if (invocation.memberName == #addStream) {
      return Future<void>.value();
    }
    return null;
  }
}

class MockHttpClientResponse implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  MockHttpClientResponse({required this.statusCode, required this.body});

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  int get contentLength => body.length;

  @override
  String get reasonPhrase => 'OK';

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => true;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final stream = Stream<List<int>>.value(utf8.encode(body));
    return stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    debugPrint('MockHttpClientResponse: missing method called: ${invocation.memberName}');
    return null;
  }
}

class MockHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  String? value(String name) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
