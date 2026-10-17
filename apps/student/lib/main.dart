import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

const backendUrl = String.fromEnvironment('SUPABASE_URL');
const backendKey = String.fromEnvironment('SUPABASE_ANON_KEY');
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? problem;
  if (backendUrl.isNotEmpty && backendKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: backendUrl, publishableKey: backendKey);
    } catch (_) {
      problem = 'Could not connect. Check the app configuration and network.';
    }
  } else {
    problem =
        'Supabase is not configured. Ask your teacher for the configured APK.';
  }
  runApp(MaterialApp(
      title: 'SecureQuiz',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176e53)),
          useMaterial3: true),
      home: StudentHome(problem: problem)));
}

class StudentHome extends StatefulWidget {
  final String? problem;
  const StudentHome({super.key, this.problem});
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> with WidgetsBindingObserver {
  final email = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController();
  Map<String, dynamic>? attempt;
  SharedPreferences? prefs;
  Timer? timer;
  WebViewController? web;
  bool busy = false, syncing = false, leaving = false;
  String message = '';
  Duration offset = Duration.zero;
  final pending = <String>[];
  SupabaseClient get db => Supabase.instance.client;
  bool get active => attempt?['status'] == 'active';
  String get queueKey => 'events_${db.auth.currentUser?.id}';
  String get codeKey => 'code_${db.auth.currentUser?.id}';
  int get seconds => attempt == null
      ? 0
      : DateTime.parse(attempt!['deadline'])
          .difference(DateTime.now().add(offset))
          .inSeconds
          .clamp(0, 10800);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.problem == null) {
      unawaited(restore());
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (active && seconds == 0 && !busy && !syncing) {
          unawaited(guard(finish));
        }
      });
    }
  }

  Future<void> restore() async {
    prefs = await SharedPreferences.getInstance();
    if (db.auth.currentUser != null) {
      pending.clear();
      pending.addAll(prefs!.getStringList(queueKey) ?? []);
      code.text = prefs!.getString(codeKey) ?? '';
      if (code.text.isNotEmpty) {
        await (busy ? join() : guard(join));
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> guard(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => message = e is AuthException
            ? e.message
            : 'Connection or request failed. Your saved progress is retained; retry when online.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void accept(dynamic data) {
    final a = Map<String, dynamic>.from(data as Map);
    offset = DateTime.parse(a['server_now']).difference(DateTime.now());
    if (mounted) setState(() => attempt = a);
  }

  Future<void> join() async {
    accept(await db.rpc('start_attempt', params: {'p_code': code.text.trim()}));
    await prefs?.setString(codeKey, code.text.trim());
    if (attempt!['mode'] != 'native' && active) {
      web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (r) {
          final u = Uri.tryParse(r.url);
          return u?.scheme == 'https'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        }))
        ..loadRequest(Uri.parse(attempt!['form_url']));
    }
    await flush();
  }

  Future<void> flush() async {
    if (syncing || attempt == null) return;
    syncing = true;
    try {
      while (pending.isNotEmpty) {
        final id = pending.first;
        accept(await db.rpc('report_violation',
            params: {'p_attempt': attempt!['id'], 'p_event': id}));
        pending.removeAt(0);
        await prefs?.setStringList(queueKey, pending);
      }
    } finally {
      syncing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!active) return;
    if (state == AppLifecycleState.paused && !leaving) {
      leaving = true;
      final id = const Uuid().v4();
      pending.add(id);
      unawaited(persistEvents());
    }
    if (state == AppLifecycleState.resumed) {
      leaving = false;
      unawaited(guard(() async {
        await flush();
        accept(await db
            .rpc('start_attempt', params: {'p_code': code.text.trim()}));
      }));
    }
  }

  Future<void> persistEvents() async {
    await prefs?.setStringList(queueKey, List<String>.from(pending));
  }

  Future<void> finish() async {
    await flush();
    accept(
        await db.rpc('finish_attempt', params: {'p_attempt': attempt!['id']}));
  }

  Future<void> answer(String question, int choice) async {
    await flush();
    if (!active) return;
    accept(await db.rpc('save_answer', params: {
      'p_attempt': attempt!['id'],
      'p_question': question,
      'p_choice': choice
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signed = widget.problem == null && db.auth.currentUser != null;
    return PopScope(
        canPop: !active,
        child: Scaffold(
            appBar: AppBar(title: const Text('SecureQuiz'), actions: [
              if (signed && !active)
                TextButton(
                    onPressed: busy
                        ? null
                        : () => guard(() async {
                              await db.auth.signOut();
                              attempt = null;
                              pending.clear();
                              code.clear();
                            }),
                    child: const Text('Sign out'))
            ]),
            body: SafeArea(
                child: Column(children: [
              if (busy) const LinearProgressIndicator(),
              if (message.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(message,
                        style: const TextStyle(color: Colors.red))),
              Expanded(
                  child: widget.problem != null
                      ? Center(
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(widget.problem!)))
                      : !signed
                          ? login()
                          : attempt == null
                              ? joinScreen()
                              : quiz())
            ]))));
  }

  Widget login() => ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Ready to learn?',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        const Text('Sign in with your student account, or create one below.'),
        TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email')),
        TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password')),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: busy
                ? null
                : () => guard(() async {
                      await db.auth.signInWithPassword(
                          email: email.text.trim(), password: password.text);
                      password.clear();
                      await restore();
                    }),
            child: const Text('Sign in')),
        TextButton(
            onPressed: busy
                ? null
                : () => guard(() async {
                      final r = await db.auth.signUp(
                          email: email.text.trim(), password: password.text);
                      password.clear();
                      message = r.session == null
                          ? 'Check your email to confirm your account, then sign in.'
                          : 'Account created.';
                      await restore();
                    }),
            child: const Text('Create student account'))
      ]);
  Widget joinScreen() => ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Join your quiz',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextField(
            controller: code,
            textCapitalization: TextCapitalization.characters,
            decoration:
                const InputDecoration(labelText: 'Teacher’s join code')),
        const SizedBox(height: 24),
        const Text(
            'During an active session, leaving the app may be reported to your teacher. Calls and system screens can also trigger reports. The switch limit ends your SecureQuiz attempt. Monitoring is best effort, not a device lockdown.'),
        const SizedBox(height: 16),
        const Text(
            'Forms mode: submit inside the form before ending the session. SecureQuiz cannot verify a Forms submission or score. Provider sign-in or browser redirects may count as leaving the app.'),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: busy ? null : () => guard(join),
            child: const Text('I understand · Start or resume'))
      ]);
  Widget quiz() {
    final a = attempt!;
    if (!active) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        Text(a['title'], style: const TextStyle(fontSize: 28)),
        Text('Session ${a['status']}'),
        const SizedBox(height: 20),
        Text(
            a['score'] == null
                ? 'Forms session ended. Confirm submission with the form provider.'
                : 'Score: ${a['score']} / ${a['max_score']}',
            style: const TextStyle(fontSize: 24)),
        Text('Reported app switches: ${a['violations']}'),
        FilledButton(
            onPressed: busy
                ? null
                : () => guard(() async {
                      await flush();
                      await prefs?.remove(codeKey);
                      setState(() {
                        attempt = null;
                        web = null;
                        code.clear();
                      });
                    }),
            child: const Text('Back to join'))
      ]);
    }
    final questions = (a['questions'] as List);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text(a['title'],
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(
                '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} remaining · switches ${a['violations']}/${a['violation_limit']}'),
            if (pending.isNotEmpty)
              const Text('App-switch reports waiting to sync')
          ])),
      Expanded(
          child: a['mode'] == 'native'
              ? ListView(padding: const EdgeInsets.all(16), children: [
                  for (final q in questions)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: RadioGroup<int>(
                                groupValue: a['answers'][q['id']] as int?,
                                onChanged: (value) {
                                  if (!busy && seconds > 0 && value != null) {
                                    unawaited(
                                        guard(() => answer(q['id'], value)));
                                  }
                                },
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(q['prompt'],
                                          style: const TextStyle(fontSize: 18)),
                                      for (var i = 0;
                                          i < (q['options'] as List).length;
                                          i++)
                                        RadioListTile<int>(
                                            title: Text(q['options'][i]),
                                            value: i,
                                            enabled: !busy && seconds > 0)
                                    ]))))
                ])
              : web == null
                  ? const Center(child: Text('Reconnect to load the form.'))
                  : WebViewWidget(controller: web!)),
      Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
              onPressed: busy
                  ? null
                  : () => guard(() async {
                        final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                                    title: Text(a['mode'] == 'native'
                                        ? 'Submit quiz?'
                                        : 'End Forms session?'),
                                    content: Text(a['mode'] == 'native'
                                        ? 'Your saved answers will be scored. You cannot change them after submission.'
                                        : 'Submit inside the provider’s form first. Ending this session does not submit it.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Continue')),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Finish'))
                                    ]));
                        if (confirm == true) await finish();
                      }),
              child: Text(a['mode'] == 'native'
                  ? 'Submit answers'
                  : 'End Forms session')))
    ]);
  }
}
