import 'dart:async';
import 'dart:convert';
import 'dart:math';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

void main() {
  runApp(const GreenBoardApp());
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

class GreenBoardApp extends StatelessWidget {
  const GreenBoardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Green Board • B-School Workspace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF06110D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Segoe UI',
      ),
      home: const GreenBoardHome(),
    );
  }
}

// Reusable Hover Scale & Glow Wrapper for Buttons, Chips, and Cards
class HoverScaleGlow extends StatefulWidget {
  final Widget child;
  final double scale;
  final Color glowColor;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final String? tooltip;

  const HoverScaleGlow({
    super.key,
    required this.child,
    this.scale = 1.05,
    this.glowColor = const Color(0xFF10B981),
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.onTap,
    this.tooltip,
  });

  @override
  State<HoverScaleGlow> createState() => _HoverScaleGlowState();
}

class _HoverScaleGlowState extends State<HoverScaleGlow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Widget content = MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isHovered = true),
        onTapUp: (_) => setState(() => _isHovered = false),
        onTapCancel: () => setState(() => _isHovered = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: widget.glowColor.withValues(alpha: 0.38),
                        blurRadius: 16,
                        spreadRadius: 1.5,
                      ),
                    ]
                  : [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: content);
    }
    return content;
  }
}

enum ViewMode { board, history, trash, feedback }

class DeadlineItem {
  final String id;
  final String title;
  final String subtitle;
  String category;
  String subCategory;
  final DateTime dueDate;
  final String source;
  final String? gmailMessageId;
  final String importance;
  bool isCompleted;
  bool isDeleted;

  DeadlineItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    this.subCategory = 'General',
    required this.dueDate,
    required this.source,
    this.gmailMessageId,
    this.importance = 'Important',
    this.isCompleted = false,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'category': category,
        'subCategory': subCategory,
        'dueDate': dueDate.toIso8601String(),
        'source': source,
        'gmailMessageId': gmailMessageId,
        'importance': importance,
        'isCompleted': isCompleted,
        'isDeleted': isDeleted,
      };

  factory DeadlineItem.fromJson(Map<String, dynamic> json) => DeadlineItem(
        id: json['id'],
        title: json['title'],
        subtitle: json['subtitle'],
        category: json['category'],
        subCategory: json['subCategory'] ?? 'General',
        dueDate: DateTime.parse(json['dueDate']),
        source: json['source'],
        gmailMessageId: json['gmailMessageId'],
        importance: json['importance'] ?? 'Important',
        isCompleted: json['isCompleted'] ?? false,
        isDeleted: json['isDeleted'] ?? false,
      );
}

class ReminderItem {
  final String id;
  final String title;
  final String subtitle;
  final String timeLabel;
  final String? gmailMessageId;
  final String source;
  bool isDone;

  ReminderItem({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.timeLabel,
    this.gmailMessageId,
    this.source = 'Gmail',
    this.isDone = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'timeLabel': timeLabel,
        'gmailMessageId': gmailMessageId,
        'source': source,
        'isDone': isDone,
      };

  factory ReminderItem.fromJson(Map<String, dynamic> json) => ReminderItem(
        id: json['id'],
        title: json['title'],
        subtitle: json['subtitle'] ?? '',
        timeLabel: json['timeLabel'],
        gmailMessageId: json['gmailMessageId'],
        source: json['source'] ?? 'Gmail',
        isDone: json['isDone'] ?? false,
      );
}

class ActionLog {
  final String id;
  final String description;
  final String actionType;
  final DateTime timestamp;
  final VoidCallback undoCallback;
  bool isReverted;

  ActionLog({
    required this.id,
    required this.description,
    required this.actionType,
    required this.timestamp,
    required this.undoCallback,
    this.isReverted = false,
  });
}

class UndoToastModel {
  final String id;
  final String message;
  final VoidCallback onUndo;

  UndoToastModel({
    required this.id,
    required this.message,
    required this.onUndo,
  });
}

class GreenBoardHome extends StatefulWidget {
  const GreenBoardHome({super.key});

  @override
  State<GreenBoardHome> createState() => _GreenBoardHomeState();
}

class _GreenBoardHomeState extends State<GreenBoardHome> with SingleTickerProviderStateMixin {
  List<String> categories = [
    'All',
    'Placements',
    'Acads / PGP',
    'Case Comps',
    'Scholarships',
    'Clubs & Comm',
  ];
  String selectedCategory = 'All';
  ViewMode currentView = ViewMode.board;
  bool showOnlyCritical = false;
  bool _isSyncing = false;
  String _syncProgressText = 'Sync';
  late TabController _statusTabController;
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/gmail.readonly',
    ],
  );

  List<DeadlineItem> deadlines = [];
  List<ReminderItem> reminders = [];
  List<ActionLog> actionHistory = [];
  List<UndoToastModel> activeUndoToasts = [];
  List<Map<String, String>> voiceBoxSubmissions = [];

  List<String> syncedAccounts = [];
  String? savedUserEmail;
  String? savedUserName;
  String? savedUserPhoto;

  Timer? _cleanupTimer;

  @override
  void initState() {
    super.initState();
    _statusTabController = TabController(length: 2, vsync: this);

    _loadDataFromLocal().then((_) {
      _runPeriodicCleanup();
      _restoreSessionAndQuickSync();
    });

    _scrollController.addListener(() {
      if (_scrollController.offset > 35 && !_isScrolled) {
        setState(() => _isScrolled = true);
      } else if (_scrollController.offset <= 35 && _isScrolled) {
        setState(() => _isScrolled = false);
      }
    });

    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _runPeriodicCleanup();
    });
  }

  Future<void> _restoreSessionAndQuickSync() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null && mounted) {
        setState(() {
          savedUserEmail = account.email;
          savedUserName = account.displayName;
          savedUserPhoto = account.photoUrl;
        });
        _saveDataToLocal();
        if (!syncedAccounts.contains(account.email)) {
          _handleGoogleGmailSync(isAuto: true);
        }
      }
    } catch (_) {}
  }

  void _openExactEmailById(String? msgId, String title, String source) {
    final accountEmail = source.contains('@')
        ? source
        : (_googleSignIn.currentUser?.email ?? savedUserEmail ?? '');

    if (msgId != null && msgId.isNotEmpty) {
      if (msgId.startsWith('http://') || msgId.startsWith('https://')) {
        html.window.open(msgId, '_blank');
        return;
      }

      final String gmailUrl = accountEmail.isNotEmpty
          ? 'https://mail.google.com/mail/?authuser=${Uri.encodeComponent(accountEmail)}#all/$msgId'
          : 'https://mail.google.com/mail/u/0/#all/$msgId';

      html.window.open(gmailUrl, '_blank');
    } else {
      final encodedQuery = Uri.encodeComponent('subject:"$title"');
      final String searchUrl = accountEmail.isNotEmpty
          ? 'https://mail.google.com/mail/?authuser=${Uri.encodeComponent(accountEmail)}#search/$encodedQuery'
          : 'https://mail.google.com/mail/u/0/#search/$encodedQuery';

      html.window.open(searchUrl, '_blank');
    }
  }

  Future<void> _handleGoogleGmailSync({
    bool isAuto = false,
    bool switchAccount = false,
    bool forceDeepScan = false,
  }) async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _syncProgressText = '...';
    });

    try {
      if (switchAccount) {
        await _googleSignIn.signOut();
      }
      GoogleSignInAccount? account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signIn();

      if (account == null) {
        setState(() {
          _isSyncing = false;
          _syncProgressText = 'Sync';
        });
        return;
      }

      savedUserEmail = account.email;
      savedUserName = account.displayName ?? 'B-School User';
      savedUserPhoto = account.photoUrl;

      final bool isFirstScanForAccount = !syncedAccounts.contains(account.email) || forceDeepScan;

      if (!mounted) return;
      if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFirstScanForAccount
                  ? 'First scan for ${account.email}: Running Deep Scan for Deadlines & Campus Reminders...'
                  : 'Quick syncing recent 30 mails for ${account.email}...',
            ),
          ),
        );
      }

      var authHeaders = await account.authHeaders;
      var authenticateClient = GoogleAuthClient(authHeaders);
      var gmailApi = gmail.GmailApi(authenticateClient);

      const String query = '-from:linkedin.com -from:insideiim.com -from:smule.com -category:social '
          '(deadline OR "application published" OR "application modified" OR "process update" OR shortlisted '
          'OR "batch meet" OR "mandatorily" OR "surprise quiz" OR "assessment form" OR "assigned reading" '
          'OR "interest form" OR "paper cribs" OR "endterm" OR "midterm" OR "scholarship" OR "nbfa" '
          'OR "submission" OR "submit" OR "round" OR "eod" OR "conclave" OR "case competition" OR "unstop" '
          'OR "parcel" OR "copy check" OR "answer sheet" OR "shuttle" OR "buggy" OR "mess" OR "library" '
          'OR "raymond" OR "decathlon" OR "venue" OR "timing" OR "closed" OR "collect" OR "schedule")';

      List<gmail.Message> allFetchedSummaries = [];

      try {
        if (isFirstScanForAccount) {
          String? pageToken;
          int pagesScanned = 0;
          do {
            setState(() => _syncProgressText = 'p.${pagesScanned + 1}');
            final messagesResponse = await gmailApi.users.messages.list(
              'me',
              q: query,
              maxResults: 100,
              pageToken: pageToken,
            );
            if (messagesResponse.messages != null) {
              allFetchedSummaries.addAll(messagesResponse.messages!);
            }
            pageToken = messagesResponse.nextPageToken;
            pagesScanned++;
          } while (pageToken != null && pagesScanned < 3);
        } else {
          setState(() => _syncProgressText = '30');
          final messagesResponse = await gmailApi.users.messages.list(
            'me',
            q: query,
            maxResults: 30,
          );
          if (messagesResponse.messages != null) {
            allFetchedSummaries.addAll(messagesResponse.messages!);
          }
        }
      } catch (err) {
        if (err.toString().contains('401')) {
          await _googleSignIn.signOut();
          account = await _googleSignIn.signIn();
          if (account == null) rethrow;
          authHeaders = await account.authHeaders;
          authenticateClient = GoogleAuthClient(authHeaders);
          gmailApi = gmail.GmailApi(authenticateClient);
          final retryResp = await gmailApi.users.messages.list('me', q: query, maxResults: 30);
          if (retryResp.messages != null) {
            allFetchedSummaries.addAll(retryResp.messages!);
          }
        } else {
          rethrow;
        }
      }

      List<Map<String, String>> rawEmails = [];
      int count = 0;

      for (var msgSummary in allFetchedSummaries) {
        if (msgSummary.id == null) continue;
        final alreadyInDeadlines = deadlines.any((d) => d.gmailMessageId == msgSummary.id || d.id == 'gmail_${msgSummary.id}');
        final alreadyInReminders = reminders.any((r) => r.gmailMessageId == msgSummary.id || r.id == 'rem_${msgSummary.id}');
        if (alreadyInDeadlines || alreadyInReminders) {
          continue;
        }

        count++;
        if (mounted) {
          setState(() => _syncProgressText = '$count');
        }

        final msg = await gmailApi.users.messages.get(
          'me',
          msgSummary.id!,
          format: 'metadata',
          metadataHeaders: ['Subject', 'From', 'Date'],
        );

        String subject = '';
        String from = '';
        String dateHeader = '';
        final headers = msg.payload?.headers ?? [];
        for (var h in headers) {
          final name = h.name?.toLowerCase();
          if (name == 'subject') subject = h.value ?? '';
          if (name == 'from') from = h.value ?? '';
          if (name == 'date') dateHeader = h.value ?? '';
        }

        String snippet = msg.snippet ?? '';
        String internalDateMs = msg.internalDate ?? DateTime.now().millisecondsSinceEpoch.toString();

        rawEmails.add({
          'id': msgSummary.id!,
          'subject': subject,
          'from': from,
          'dateHeader': dateHeader,
          'internalDateMs': internalDateMs,
          'snippet': snippet,
          'accountEmail': account.email,
        });
      }

      final newDeadlines = parseEmailsToDeadlines(rawEmails);
      final newReminders = parseEmailsToReminders(rawEmails);

      if (!syncedAccounts.contains(account.email)) {
        syncedAccounts.add(account.email);
      }

      if (!mounted) return;

      final now = DateTime.now();
      setState(() {
        deadlines.removeWhere((d) => d.dueDate.isBefore(now) && !d.isCompleted);
        deadlines.addAll(newDeadlines);
        reminders.insertAll(0, newReminders);
      });
      await _saveDataToLocal();

      if (newDeadlines.isNotEmpty || newReminders.isNotEmpty) {
        _recordAction(
          description: 'Synced ${newDeadlines.length} deadlines & ${newReminders.length} reminders',
          actionType: 'sync',
          onUndo: () {
            setState(() {
              for (var item in newDeadlines) {
                deadlines.removeWhere((d) => d.id == item.id);
              }
              for (var rem in newReminders) {
                reminders.removeWhere((r) => r.id == rem.id);
              }
            });
            _saveDataToLocal();
          },
        );
      } else if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync complete — you are all caught up!'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gmail Sync Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgressText = 'Sync';
        });
      }
    }
  }

  List<ReminderItem> parseEmailsToReminders(List<Map<String, String>> rawEmails) {
    List<ReminderItem> extractedReminders = [];
    final now = DateTime.now();

    for (var email in rawEmails) {
      String msgId = email['id'] ?? '';
      String subject = (email['subject'] ?? '').trim();
      String snippet = (email['snippet'] ?? '').trim();
      String from = (email['from'] ?? '').trim();
      String accountEmail = email['accountEmail'] ?? 'Gmail';
      int sentEpoch = int.tryParse(email['internalDateMs'] ?? '') ?? now.millisecondsSinceEpoch;
      DateTime emailSentDate = DateTime.fromMillisecondsSinceEpoch(sentEpoch);

      if (now.difference(emailSentDate).inDays > 7) continue;

      final combined = '$subject $snippet'.toLowerCase();

      bool isCampusScheduleOrReminder = combined.contains('parcel') ||
          combined.contains('copy check') ||
          combined.contains('paper cribs') ||
          combined.contains('answer sheet') ||
          combined.contains('shuttle') ||
          combined.contains('buggy') ||
          combined.contains('raymond') ||
          combined.contains('decathlon') ||
          combined.contains('lost and found') ||
          combined.contains('movie of this week') ||
          combined.contains('batch meet') ||
          combined.contains('library') ||
          combined.contains('mess') ||
          combined.contains('dispensary') ||
          combined.contains('timing') ||
          combined.contains('closed') ||
          combined.contains('collect') ||
          combined.contains('venue');

      if (!isCampusScheduleOrReminder) continue;

      final timeRegex = RegExp(r'\b(\d{1,2}(?::\d{2})?\s*(?:am|pm))\b', caseSensitive: false);
      final timeMatch = timeRegex.firstMatch('$subject $snippet');
      String timeBadge = timeMatch != null
          ? timeMatch.group(1)!.toUpperCase()
          : '${emailSentDate.day}/${emailSentDate.month}';

      extractedReminders.add(
        ReminderItem(
          id: 'rem_$msgId',
          title: _cleanTitle(subject),
          subtitle: snippet.isNotEmpty ? snippet : 'From: $from',
          timeLabel: timeBadge,
          gmailMessageId: msgId,
          source: accountEmail,
        ),
      );
    }

    return extractedReminders;
  }

  List<DeadlineItem> parseEmailsToDeadlines(List<Map<String, String>> rawEmails) {
    List<DeadlineItem> parsedDeadlines = [];
    final now = DateTime.now();

    for (var email in rawEmails) {
      String msgId = email['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
      String subject = (email['subject'] ?? '').trim();
      String from = (email['from'] ?? '').trim();
      String snippet = (email['snippet'] ?? '').trim();
      String accountEmail = email['accountEmail'] ?? 'Gmail';
      int sentEpoch = int.tryParse(email['internalDateMs'] ?? '') ?? now.millisecondsSinceEpoch;
      DateTime emailSentDate = DateTime.fromMillisecondsSinceEpoch(sentEpoch);

      String importance = _analyzeEmailImportance(subject, snippet, from);
      if (importance == 'Spam' || importance == 'Low') {
        continue;
      }

      DateTime? extractedDate = _extractDueDateFromText(
        subject: subject,
        snippet: snippet,
        emailSentDate: emailSentDate,
      );

      if (extractedDate == null || extractedDate.isBefore(now)) {
        continue;
      }

      final category = _autoClassifyEmail(subject, snippet, from);
      final subCategory = _extractSubCategory('$subject $snippet'.toLowerCase(), from.toLowerCase());

      parsedDeadlines.add(
        DeadlineItem(
          id: 'gmail_$msgId',
          title: _cleanTitle(subject),
          subtitle: snippet.isNotEmpty ? snippet : 'Action required from $from',
          category: category,
          subCategory: subCategory,
          dueDate: extractedDate,
          source: accountEmail,
          gmailMessageId: msgId,
          importance: importance,
        ),
      );
    }

    return parsedDeadlines;
  }

  String _cleanTitle(String subject) {
    if (subject.isEmpty) return 'Action Required';
    return subject.replaceAll(RegExp(r'^(Fwd:|Re:)\s*', caseSensitive: false), '').trim();
  }

  String _analyzeEmailImportance(String subject, String snippet, String from) {
    final s = subject.toLowerCase();
    final b = snippet.toLowerCase();
    final f = from.toLowerCase();
    final combined = '$s $b';

    if (f.contains('linkedin') ||
        f.contains('insideiim') ||
        f.contains('jia from unstop') ||
        f.contains('amex') ||
        f.contains('smule') ||
        s.contains('appeared in recent searches') ||
        s.contains('viewed your profile') ||
        s.contains('shared their thoughts on linkedin') ||
        s.contains('you may know') ||
        s.contains('cat 2026') ||
        s.contains('cat mistakes') ||
        s.contains('victory mocks') ||
        s.contains('earn inr 1 lakh stipend') ||
        s.contains('earn stipend upto') ||
        s.contains('your skills + these opportunities') ||
        s.contains('email otp') ||
        s.contains('security alert') ||
        s.contains('verify your account')) {
      return 'Spam';
    }

    if (s.startsWith('grades of ') ||
        s.startsWith('updated grades of ') ||
        s.contains('marks list') ||
        s.contains('ips marks') ||
        s.contains('spreadsheet shared with you') ||
        s.contains('attendance sheets for') ||
        s.contains('attendance guidelines') ||
        s.contains('registered successfully') ||
        s.contains('registration complete') ||
        s.contains('application submit -') ||
        s.contains('thank you! you are now following') ||
        s.contains('you\'ve earned it! certificate') ||
        s.contains('winners announcement') ||
        s.contains('the winners are in!') ||
        s.contains('lost and found') ||
        s.contains('खोया और पाया') ||
        s.contains('movie of this week') ||
        s.contains('इस सप्ताह का चलचित्र') ||
        s.contains('shuttle buggy service') ||
        s.contains('raymond on campus') ||
        s.contains('decathlon on campus') ||
        s.contains('qbits |') ||
        s.contains('ai bits |') ||
        s.contains('finshots college weekly') ||
        s.contains('stock of the week') ||
        s.contains('weekly market wrap') ||
        s.contains('macroscan ||') ||
        s.contains('yourdost') ||
        s.contains('colors of planet-i') ||
        s.contains('ppt of finance')) {
      return 'Low';
    }

    if (s.contains('application published for') ||
        s.contains('application modified for') ||
        s.contains('process update ||') ||
        s.contains('ppt ||') ||
        s.contains('placement batch meet') ||
        s.contains('surprise quiz') ||
        s.contains('cp assessment form') ||
        s.contains('endterm') ||
        s.contains('paper cribs') ||
        s.contains('need based financial assistance') ||
        s.contains('central sector scholarship') ||
        combined.contains('shortlisted for') ||
        combined.contains('mandatorily') ||
        combined.contains('deadline for completing the application')) {
      return 'Very Important';
    }

    if (combined.contains('deadline') ||
        combined.contains('submission') ||
        combined.contains('submit') ||
        combined.contains('interest form') ||
        combined.contains('assigned reading') ||
        combined.contains('report guidelines') ||
        combined.contains('confirmation pending') ||
        combined.contains('complete your team') ||
        combined.contains('only 1 day remains') ||
        combined.contains('final call') ||
        combined.contains('by eod') ||
        combined.contains('scheduled on')) {
      return 'Important';
    }

    return 'Low';
  }

  String _autoClassifyEmail(String subject, String body, String from) {
    final text = '${subject.toLowerCase()} ${body.toLowerCase()} ${from.toLowerCase()}';
    if (text.contains('scholarship') || text.contains('financial assistance') || text.contains('nbfa') || text.contains('buddy4study')) {
      return 'Scholarships';
    } else if (text.contains('application published') ||
        text.contains('application modified') ||
        text.contains('process update') ||
        text.contains('placement') ||
        text.contains('placecom') ||
        text.contains('prepcom') ||
        text.contains('ppt ||') ||
        text.contains('shortlisted') ||
        text.contains('cv') ||
        text.contains('npad')) {
      return 'Placements';
    } else if (text.contains('unstop') ||
        text.contains('sun prism') ||
        text.contains('ace the case') ||
        text.contains('hrace') ||
        text.contains('tvs motor') ||
        text.contains('best manager') ||
        text.contains('case competition') ||
        text.contains('ideathon')) {
      return 'Case Comps';
    } else if (text.contains('quiz') ||
        text.contains('cp assessment') ||
        text.contains('assigned reading') ||
        text.contains('paper cribs') ||
        text.contains('endterm') ||
        text.contains('rep2026') ||
        text.contains('session') ||
        text.contains('prof.') ||
        text.contains('pgp')) {
      return 'Acads / PGP';
    } else if (text.contains('interest form') ||
        text.contains('cul-com') ||
        text.contains('mess') ||
        text.contains('sports') ||
        text.contains('section wars') ||
        text.contains('garba') ||
        text.contains('durga puja') ||
        text.contains('industry visit') ||
        text.contains('conclave') ||
        text.contains('mercur-i') ||
        text.contains('e-cell') ||
        text.contains('kaizen')) {
      return 'Clubs & Comm';
    }
    return 'Acads / PGP';
  }

  String _extractSubCategory(String text, String from) {
    if (text.contains('application published') || text.contains('application modified')) return 'Role Application';
    if (text.contains('process update') || text.contains('shortlisted')) return 'GD / PI Shortlist';
    if (text.contains('ppt ||')) return 'Pre-Placement Talk';
    if (text.contains('batch meet')) return 'Batch Meet';
    if (text.contains('quiz')) return 'Quiz';
    if (text.contains('cp assessment')) return 'CP Form';
    if (text.contains('assigned reading')) return 'Pre-Read';
    if (text.contains('paper cribs') || text.contains('endterm')) return 'Exam / Cribs';
    if (text.contains('rep2026')) return 'REP Report';
    if (text.contains('interest form')) return 'Interest Form';
    if (text.contains('nbfa') || text.contains('scholarship')) return 'Financial Aid';
    if (text.contains('confirmation pending') || text.contains('complete your team')) return 'Team Action';
    if (text.contains('round 1')) return 'Round 1';
    if (text.contains('round 2')) return 'Round 2';
    return 'Action Item';
  }

  DateTime? _extractDueDateFromText({
    required String subject,
    required String snippet,
    required DateTime emailSentDate,
  }) {
    final text = '$subject $snippet'.toLowerCase();

    final months = {
      'jan': 1, 'january': 1,
      'feb': 2, 'february': 2,
      'mar': 3, 'march': 3,
      'apr': 4, 'april': 4,
      'may': 5,
      'jun': 6, 'june': 6,
      'jul': 7, 'july': 7,
      'aug': 8, 'august': 8,
      'sep': 9, 'sept': 9, 'september': 9,
      'oct': 10, 'october': 10,
      'nov': 11, 'november': 11,
      'dec': 12, 'december': 12,
    };

    int? extractedDay;
    int? extractedMonth;
    int extractedYear = emailSentDate.year;

    final regexDayFirst = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)(?:\s*,?\s*(202\d))?\b',
    );
    final match1 = regexDayFirst.firstMatch(text);
    if (match1 != null) {
      extractedDay = int.tryParse(match1.group(1)!);
      extractedMonth = months[match1.group(2)!];
      if (match1.group(3) != null) {
        extractedYear = int.parse(match1.group(3)!);
      }
    }

    if (extractedDay == null) {
      final regexMonthFirst = RegExp(
        r'\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s*,?\s*(202\d))?\b',
      );
      final match2 = regexMonthFirst.firstMatch(text);
      if (match2 != null) {
        extractedMonth = months[match2.group(1)!];
        extractedDay = int.tryParse(match2.group(2)!);
        if (match2.group(3) != null) {
          extractedYear = int.parse(match2.group(3)!);
        }
      }
    }

    if (extractedDay == null) {
      final regexNumeric = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](202\d)\b');
      final match3 = regexNumeric.firstMatch(text);
      if (match3 != null) {
        extractedDay = int.tryParse(match3.group(1)!);
        extractedMonth = int.tryParse(match3.group(2)!);
        extractedYear = int.parse(match3.group(3)!);
      }
    }

    if (extractedDay == null) {
      if (text.contains('tomorrow') || text.contains('only 1 day remains')) {
        final tom = emailSentDate.add(const Duration(days: 1));
        extractedDay = tom.day;
        extractedMonth = tom.month;
        extractedYear = tom.year;
      } else if (text.contains('today') || text.contains('tonight') || text.contains('by eod')) {
        extractedDay = emailSentDate.day;
        extractedMonth = emailSentDate.month;
        extractedYear = emailSentDate.year;
      } else if (text.contains('few hours left') || text.contains('final call') || text.contains('complete your team')) {
        return emailSentDate.add(const Duration(hours: 36));
      } else if (text.contains('gentle reminder') || text.contains('interest form') || text.contains('report guidelines')) {
        return emailSentDate.add(const Duration(hours: 48));
      }
    }

    if (extractedDay == null || extractedMonth == null) {
      return null;
    }

    int hour = 23;
    int minute = 59;

    final timeRegex = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b');
    final timeMatch = timeRegex.firstMatch(text);
    if (timeMatch != null) {
      int rawHour = int.parse(timeMatch.group(1)!);
      int rawMin = timeMatch.group(2) != null ? int.parse(timeMatch.group(2)!) : 0;
      String amPm = timeMatch.group(3)!.toLowerCase();

      if (amPm == 'pm' && rawHour < 12) rawHour += 12;
      if (amPm == 'am' && rawHour == 12) rawHour = 0;

      hour = rawHour;
      minute = rawMin;
    }

    return DateTime(extractedYear, extractedMonth, extractedDay, hour, minute);
  }

  String _extractMsgIdFromInput(String input) {
    final trimmed = input.trim();
    if (!trimmed.contains('/')) return trimmed;
    final parts = trimmed.split('/');
    final lastPart = parts.last.split('?').first;
    return lastPart;
  }

  @override
  void dispose() {
    _statusTabController.dispose();
    _scrollController.dispose();
    _cleanupTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDataFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCats = prefs.getStringList('saved_categories');
    if (savedCats != null && savedCats.isNotEmpty) {
      categories = savedCats;
    }

    syncedAccounts = prefs.getStringList('synced_accounts') ?? [];
    savedUserEmail = prefs.getString('saved_user_email');
    savedUserName = prefs.getString('saved_user_name');
    savedUserPhoto = prefs.getString('saved_user_photo');

    final savedDeadlinesJson = prefs.getStringList('saved_deadlines');
    if (savedDeadlinesJson != null && savedDeadlinesJson.isNotEmpty) {
      final loaded = savedDeadlinesJson
          .map((item) => DeadlineItem.fromJson(jsonDecode(item)))
          .where((item) => item.id != '1' && item.id != '2' && item.id != '3')
          .toList();
      setState(() {
        deadlines = loaded;
      });
    }

    final savedRemindersJson = prefs.getStringList('saved_reminders');
    if (savedRemindersJson != null) {
      final loadedRem = savedRemindersJson
          .map((r) => ReminderItem.fromJson(jsonDecode(r)))
          .where((r) => r.id != 'r1' && r.id != 'r2')
          .toList();
      setState(() {
        reminders = loadedRem;
      });
    }
  }

  Future<void> _saveDataToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_categories', categories);
    await prefs.setStringList('synced_accounts', syncedAccounts);
    if (savedUserEmail != null) await prefs.setString('saved_user_email', savedUserEmail!);
    if (savedUserName != null) await prefs.setString('saved_user_name', savedUserName!);
    if (savedUserPhoto != null) await prefs.setString('saved_user_photo', savedUserPhoto!);

    final deadlinesJson = deadlines.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList('saved_deadlines', deadlinesJson);

    final remindersJson = reminders.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList('saved_reminders', remindersJson);
  }

  void _runPeriodicCleanup() {
    final now = DateTime.now();
    setState(() {
      deadlines.removeWhere((item) => now.difference(item.dueDate).inHours >= 48);
      actionHistory.removeWhere((log) => now.difference(log.timestamp).inHours >= 24);
    });
    _saveDataToLocal();
  }

  void _addUndoToast(String message, VoidCallback onUndo) {
    final toastId = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      activeUndoToasts.add(
        UndoToastModel(
          id: toastId,
          message: message,
          onUndo: () {
            onUndo();
            _removeUndoToast(toastId);
          },
        ),
      );
    });
  }

  void _removeUndoToast(String id) {
    setState(() {
      activeUndoToasts.removeWhere((t) => t.id == id);
    });
  }

  void _recordAction({
    required String description,
    required String actionType,
    required VoidCallback onUndo,
  }) {
    final logItem = ActionLog(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      description: description,
      actionType: actionType,
      timestamp: DateTime.now(),
      undoCallback: onUndo,
    );

    setState(() {
      actionHistory.insert(0, logItem);
      actionHistory.removeWhere((log) => DateTime.now().difference(log.timestamp).inHours >= 24);
    });

    _addUndoToast(description, () {
      if (!logItem.isReverted) {
        logItem.undoCallback();
        setState(() => logItem.isReverted = true);
        _saveDataToLocal();
      }
    });
    _saveDataToLocal();
  }

  void _toggleComplete(DeadlineItem item, bool? val) {
    setState(() {
      item.isCompleted = val ?? false;
    });
    _saveDataToLocal();
  }

  void _moveToTrash(DeadlineItem item) {
    setState(() => item.isDeleted = true);
    _recordAction(
      description: 'Moved "${item.title}" to Trash',
      actionType: 'delete',
      onUndo: () => setState(() => item.isDeleted = false),
    );
  }

  void _restoreFromTrash(DeadlineItem item) {
    setState(() => item.isDeleted = false);
    _recordAction(
      description: 'Restored "${item.title}"',
      actionType: 'restore',
      onUndo: () => setState(() => item.isDeleted = true),
    );
  }

  void _deletePermanently(DeadlineItem item) {
    final index = deadlines.indexOf(item);
    setState(() => deadlines.remove(item));
    _recordAction(
      description: 'Deleted "${item.title}" permanently',
      actionType: 'delete',
      onUndo: () {
        setState(() {
          if (index >= 0 && index <= deadlines.length) {
            deadlines.insert(index, item);
          } else {
            deadlines.add(item);
          }
        });
        _saveDataToLocal();
      },
    );
  }

  Color _getUrgencyColor(DateTime dueDate) {
    final hoursLeft = dueDate.difference(DateTime.now()).inHours;
    if (hoursLeft < 0) return const Color(0xFFEF4444);
    if (hoursLeft <= 24) return const Color(0xFFF43F5E);
    if (hoursLeft <= 72) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  String _formatRemainingTime(DateTime dueDate) {
    final diff = dueDate.difference(DateTime.now());
    if (diff.isNegative) {
      return 'Overdue ${diff.inHours.abs()}h';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ${diff.inMinutes % 60}m left';
    }
    return '${diff.inDays}d ${diff.inHours % 24}h left';
  }

  void _showEmailSummaryDialog(DeadlineItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F221A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        title: Row(
          children: [
            const Icon(Icons.mail_outline_rounded, color: Color(0xFF34D399), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text('Category: ${item.category}', style: const TextStyle(fontSize: 12, color: Color(0xFF34D399), fontWeight: FontWeight.w600)),
                    Text('Type: ${item.subCategory}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    Text('Priority: ${item.importance}', style: const TextStyle(fontSize: 12, color: Color(0xFFFBBF24), fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Extracted Email Summary:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54)),
              const SizedBox(height: 6),
              Text(
                item.subtitle,
                style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFFFBBF24)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Deadline: ${item.dueDate.day}/${item.dueDate.month}/${item.dueDate.year} at ${item.dueDate.hour}:${item.dueDate.minute.toString().padLeft(2, '0')} (${_formatRemainingTime(item.dueDate)})',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFFBBF24), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Source Account: ${item.source}',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF34D399),
              side: BorderSide(color: const Color(0xFF34D399).withValues(alpha: 0.5)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _openExactEmailById(item.gmailMessageId, item.title, item.source);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('Open Exact Mail', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 820;

    final criticalCount = deadlines.where((item) {
      if (item.isDeleted || item.isCompleted) return false;
      return item.dueDate.difference(DateTime.now()).inHours <= 24;
    }).length;

    List<DeadlineItem> baseFiltered = deadlines.where((item) {
      if (currentView == ViewMode.trash) return item.isDeleted;
      if (item.isDeleted) return false;
      if (showOnlyCritical) {
        return item.dueDate.difference(DateTime.now()).inHours <= 24 && !item.isCompleted;
      }
      if (selectedCategory != 'All' && item.category != selectedCategory) return false;
      return true;
    }).toList();

    List<DeadlineItem> pendingItems = baseFiltered.where((i) => !i.isCompleted).toList();
    List<DeadlineItem> completedItems = baseFiltered.where((i) => i.isCompleted).toList();

    pendingItems.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    completedItems.sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return Scaffold(
      backgroundColor: const Color(0xFF050E0A),
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              margin: EdgeInsets.all(isWideScreen ? 14 : 6),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF08150F),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF5A381E).withValues(alpha: 0.55),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: InteractiveParticleBackground(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopHeader(isWideScreen),

                    if (currentView == ViewMode.board) ...[
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: _isScrolled
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildHeroBanner(criticalCount, isWideScreen),
                                  _buildRemindersStrip(),
                                ],
                              ),
                      ),
                      _buildCategoryFilterBar(criticalCount),
                      _buildPendingCompletedTabs(pendingItems.length, completedItems.length),
                    ],

                    Expanded(
                      child: currentView == ViewMode.history
                          ? _buildHistoryView()
                          : currentView == ViewMode.trash
                              ? _buildScrollableDeadlinesView(baseFiltered, isWideScreen)
                              : currentView == ViewMode.feedback
                                  ? _buildVoiceBoxView()
                                  : TabBarView(
                                      controller: _statusTabController,
                                      children: [
                                        _buildScrollableDeadlinesView(pendingItems, isWideScreen),
                                        _buildScrollableDeadlinesView(completedItems, isWideScreen),
                                      ],
                                    ),
                    ),
                  ],
                ),
              ),
            ),
            if (activeUndoToasts.isNotEmpty)
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: activeUndoToasts.map((toast) {
                        return Padding(
                          key: ValueKey(toast.id),
                          padding: const EdgeInsets.only(top: 8),
                          child: _UndoBarWidget(
                            message: toast.message,
                            onUndo: toast.onUndo,
                            onDismiss: () => _removeUndoToast(toast.id),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(bool isWide) {
    final trashCount = deadlines.where((d) => d.isDeleted).length;
    final historyCount = actionHistory.where((a) => !a.isReverted).length;

    final currentUserEmail = _googleSignIn.currentUser?.email ?? savedUserEmail ?? 'Not signed in';
    final currentUserName = _googleSignIn.currentUser?.displayName ?? savedUserName ?? 'B-School User';
    final currentUserPhoto = _googleSignIn.currentUser?.photoUrl ?? savedUserPhoto;
    final bool hasDoneDeepScan = currentUserEmail != 'Not signed in' && syncedAccounts.contains(currentUserEmail);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 20 : 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              HoverScaleGlow(
                scale: 1.08,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_rounded, color: Color(0xFF34D399), size: 16),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'GREEN BOARD',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        letterSpacing: 0.9,
                        color: Color(0xFFECFDF5),
                      ),
                    ),
                    Text(
                      'B-School Workspace',
                      style: TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              if (isWide && !_isScrolled) ...[
                _buildFiveIconButtonsRow(hasDoneDeepScan, historyCount, trashCount),
                const SizedBox(width: 10),
              ],
              _buildProfilePopupMenu(
                currentUserName: currentUserName,
                currentUserEmail: currentUserEmail,
                currentUserPhoto: currentUserPhoto,
                hasDoneDeepScan: hasDoneDeepScan,
                historyCount: historyCount,
                trashCount: trashCount,
              ),
            ],
          ),
          if (!isWide)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _isScrolled
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildFiveIconButtonsRow(hasDoneDeepScan, historyCount, trashCount),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildFiveIconButtonsRow(bool hasDoneDeepScan, int historyCount, int trashCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: [
        _buildIconOnlyActionButton(
          icon: Icons.mail_outline_rounded,
          tooltip: hasDoneDeepScan ? 'Quick Sync (30)' : 'Deep Sync Gmail',
          badgeText: _isSyncing ? _syncProgressText : (hasDoneDeepScan ? '30' : '↻'),
          isActive: _isSyncing,
          accentColor: const Color(0xFFFBBF24),
          isLoading: _isSyncing,
          onTap: _isSyncing ? () {} : () => _handleGoogleGmailSync(isAuto: false),
        ),
        const SizedBox(width: 6),
        _buildIconOnlyActionButton(
          icon: Icons.dashboard_rounded,
          tooltip: 'Board',
          isActive: currentView == ViewMode.board,
          onTap: () => setState(() => currentView = ViewMode.board),
        ),
        const SizedBox(width: 6),
        _buildIconOnlyActionButton(
          icon: Icons.history_rounded,
          tooltip: '24h History',
          badgeText: historyCount > 0 ? '$historyCount' : null,
          isActive: currentView == ViewMode.history,
          onTap: () => setState(() => currentView = ViewMode.history),
        ),
        const SizedBox(width: 6),
        _buildIconOnlyActionButton(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Trash',
          badgeText: trashCount > 0 ? '$trashCount' : null,
          isActive: currentView == ViewMode.trash,
          onTap: () => setState(() => currentView = ViewMode.trash),
        ),
        const SizedBox(width: 6),
        _buildIconOnlyActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          tooltip: 'Voice Box',
          isActive: currentView == ViewMode.feedback,
          onTap: () => setState(() => currentView = ViewMode.feedback),
        ),
      ],
    );
  }

  Widget _buildIconOnlyActionButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
    String? badgeText,
    Color? accentColor,
    bool isLoading = false,
  }) {
    final color = accentColor ?? (isActive ? const Color(0xFF34D399) : Colors.white70);
    return HoverScaleGlow(
      scale: 1.09,
      glowColor: color,
      borderRadius: BorderRadius.circular(10),
      tooltip: tooltip,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.22)
              : (accentColor != null ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? color : color.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isLoading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                : Icon(icon, size: 16, color: color),
            if (badgeText != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfilePopupMenu({
    required String currentUserName,
    required String currentUserEmail,
    required String? currentUserPhoto,
    required bool hasDoneDeepScan,
    required int historyCount,
    required int trashCount,
  }) {
    return HoverScaleGlow(
      scale: 1.07,
      glowColor: const Color(0xFF34D399),
      borderRadius: BorderRadius.circular(10),
      child: PopupMenuButton<String>(
        offset: const Offset(0, 42),
        color: const Color(0xFF0F221A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
        ),
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Active Account', style: TextStyle(fontSize: 10.5, color: Colors.white54)),
                const SizedBox(height: 2),
                Text(
                  currentUserName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                ),
                Text(
                  currentUserEmail,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
                const Divider(color: Colors.white24, height: 14),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'nav_sync',
            child: Row(
              children: [
                const Icon(Icons.mail_outline_rounded, size: 16, color: Color(0xFFFBBF24)),
                const SizedBox(width: 10),
                Text(hasDoneDeepScan ? 'Quick Sync (30)' : 'Sync Gmail', style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'nav_board',
            child: Row(
              children: [
                Icon(Icons.dashboard_rounded, size: 16, color: Color(0xFF34D399)),
                SizedBox(width: 10),
                Text('Board View', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'nav_history',
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 16, color: Colors.white70),
                const SizedBox(width: 10),
                Text('24h History ($historyCount)', style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'nav_trash',
            child: Row(
              children: [
                const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.white70),
                const SizedBox(width: 10),
                Text('Trash ($trashCount)', style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'nav_voice',
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 16, color: Colors.white70),
                SizedBox(width: 10),
                Text('Voice Box', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'switch_account',
            child: Row(
              children: [
                Icon(Icons.person_add_alt_1_rounded, size: 16, color: Color(0xFFFBBF24)),
                SizedBox(width: 10),
                Text('Sync Another Gmail ID', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'force_deep_scan',
            child: Row(
              children: [
                Icon(Icons.radar_rounded, size: 16, color: Color(0xFF34D399)),
                SizedBox(width: 10),
                Text('Force Full Deep Scan', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'how_to_use',
            child: Row(
              children: [
                Icon(Icons.help_outline_rounded, size: 16, color: Color(0xFF34D399)),
                SizedBox(width: 10),
                Text('How to Use', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          const PopupMenuItem<String>(
            value: 'about',
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF34D399)),
                SizedBox(width: 10),
                Text('About Green Board', style: TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout_rounded, size: 16, color: Color(0xFFF43F5E)),
                SizedBox(width: 10),
                Text('Logout', style: TextStyle(fontSize: 12.5, color: Color(0xFFF43F5E))),
              ],
            ),
          ),
        ],
        onSelected: (String value) {
          if (value == 'nav_sync') {
            _handleGoogleGmailSync(isAuto: false);
          } else if (value == 'nav_board') {
            setState(() => currentView = ViewMode.board);
          } else if (value == 'nav_history') {
            setState(() => currentView = ViewMode.history);
          } else if (value == 'nav_trash') {
            setState(() => currentView = ViewMode.trash);
          } else if (value == 'nav_voice') {
            setState(() => currentView = ViewMode.feedback);
          } else if (value == 'switch_account') {
            _handleGoogleGmailSync(isAuto: false, switchAccount: true);
          } else if (value == 'force_deep_scan') {
            _handleGoogleGmailSync(isAuto: false, forceDeepScan: true);
          } else if (value == 'how_to_use') {
            _showHowToUseDialog();
          } else if (value == 'about') {
            _showAboutDialog();
          } else if (value == 'logout') {
            _handleLogout();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isScrolled ? const Color(0xFF34D399).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.3),
                backgroundImage: currentUserPhoto != null ? NetworkImage(currentUserPhoto) : null,
                child: currentUserPhoto == null
                    ? Text(
                        currentUserName.isNotEmpty ? currentUserName[0].toUpperCase() : 'B',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF34D399), fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner(int criticalCount, bool isWide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 20 : 12, 10, isWide ? 20 : 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: isWide ? 24 : 18,
                      fontWeight: FontWeight.w300,
                      color: const Color(0xFFF1F5F9),
                      fontFamily: 'Georgia',
                    ),
                    children: const [
                      TextSpan(text: 'Your deadlines, '),
                      TextSpan(
                        text: 'under control.',
                        style: TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF34D399), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Placements, Acads, Case Comps & Live Campus Schedule.',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          HoverScaleGlow(
            scale: 1.08,
            glowColor: const Color(0xFFFBBF24),
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => showOnlyCritical = !showOnlyCritical),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: showOnlyCritical ? const Color(0xFFF59E0B).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: showOnlyCritical ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFBBF24), size: 14),
                  const SizedBox(width: 5),
                  Text(
                    '$criticalCount crit',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemindersStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 13, color: Color(0xFFFBBF24)),
              const SizedBox(width: 5),
              Text(
                'CAMPUS REMINDERS & SCHEDULE (${reminders.length})',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.7, color: Colors.white70),
              ),
              const Spacer(),
              HoverScaleGlow(
                scale: 1.08,
                glowColor: const Color(0xFF34D399),
                borderRadius: BorderRadius.circular(6),
                onTap: _showAddReminderDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35)),
                  ),
                  child: const Text(
                    '+ Reminder',
                    style: TextStyle(fontSize: 10, color: Color(0xFF34D399), fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: reminders.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sync Gmail to auto-fetch campus timings (parcel, cribs, shuttle) or tap "+ Reminder".',
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.38)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    itemCount: reminders.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final r = reminders[index];
                      return HoverScaleGlow(
                        scale: 1.04,
                        glowColor: const Color(0xFFFBBF24),
                        borderRadius: BorderRadius.circular(10),
                        onTap: r.gmailMessageId != null
                            ? () => _openExactEmailById(r.gmailMessageId, r.title, r.source)
                            : () {
                                setState(() => r.isDone = !r.isDone);
                                _saveDataToLocal();
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() => r.isDone = !r.isDone);
                                  _saveDataToLocal();
                                },
                                child: Container(
                                  width: 15,
                                  height: 15,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: r.isDone ? const Color(0xFF10B981) : Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: r.isDone ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                      width: 1.3,
                                    ),
                                  ),
                                  child: r.isDone
                                      ? const Icon(Icons.check_rounded, size: 10, color: Colors.black)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 210),
                                child: Text(
                                  r.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    decoration: r.isDone ? TextDecoration.lineThrough : null,
                                    color: r.isDone ? Colors.white38 : Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFBBF24).withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  r.timeLabel,
                                  style: const TextStyle(fontSize: 9.5, color: Color(0xFFFBBF24), fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  setState(() => reminders.removeAt(index));
                                  _saveDataToLocal();
                                },
                                child: const Text(
                                  '✕',
                                  style: TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterBar(int criticalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  ...categories.map((cat) {
                    bool isSelected = selectedCategory == cat && !showOnlyCritical;
                    final count = cat == 'All'
                        ? deadlines.where((d) => !d.isDeleted && !d.isCompleted).length
                        : deadlines.where((d) => !d.isDeleted && !d.isCompleted && d.category == cat).length;

                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: HoverScaleGlow(
                        scale: 1.06,
                        glowColor: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(() {
                          selectedCategory = cat;
                          showOnlyCritical = false;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF10B981) : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF34D399) : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF05110C) : Colors.white,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? const Color(0xFF05110C) : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          HoverScaleGlow(
            scale: 1.12,
            glowColor: const Color(0xFF34D399),
            borderRadius: BorderRadius.circular(14),
            tooltip: 'Add Section',
            onTap: _showAddSectionDialog,
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.45)),
              ),
              child: const Text(
                '+',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF34D399),
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCompletedTabs(int pendingCount, int completedCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TabBar(
                controller: _statusTabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: const Color(0xFF10B981),
                labelColor: const Color(0xFF34D399),
                unselectedLabelColor: Colors.white54,
                labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                tabs: [
                  Tab(text: 'Pending ($pendingCount)'),
                  Tab(text: 'Completed ($completedCount)'),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('Local', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.45))),
              const SizedBox(width: 8),
              HoverScaleGlow(
                scale: 1.1,
                glowColor: const Color(0xFF34D399),
                borderRadius: BorderRadius.circular(9),
                tooltip: 'Add Deadline or Analyze Gmail Link',
                onTap: _showManualAddDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.add_link_rounded, size: 15, color: Color(0xFF34D399)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddReminderDialog() {
    final titleCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: 'Today, 6:00 PM');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F221A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Campus Reminder', style: TextStyle(fontSize: 15, color: Color(0xFF34D399))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Task (e.g., Copy check / Parcel house)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: timeCtrl,
              decoration: const InputDecoration(
                labelText: 'Timing (e.g., Today 6:00 PM)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) return;
              setState(() {
                reminders.insert(
                  0,
                  ReminderItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: titleCtrl.text.trim(),
                    timeLabel: timeCtrl.text.trim().isEmpty ? 'Scheduled' : timeCtrl.text.trim(),
                    source: 'Manual',
                  ),
                );
              });
              _saveDataToLocal();
              Navigator.pop(context);
            },
            child: const Text('Add', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    try {
      await _googleSignIn.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_user_email');
      await prefs.remove('saved_user_name');
      await prefs.remove('saved_user_photo');
      setState(() {
        savedUserEmail = null;
        savedUserName = null;
        savedUserPhoto = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out of Google session. Your saved board deadlines remain intact.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout Error: $e')),
      );
    }
  }

  void _showHowToUseDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F221A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('How to Use Green Board', style: TextStyle(fontSize: 16, color: Color(0xFF34D399))),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('1. Minimal Icon Bar & Auto-Collapse:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Top action buttons use clean icons. When you scroll down, they tuck neatly inside your top-right Profile Menu so your deadlines get full screen space.', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
              SizedBox(height: 10),
              Text('2. Auto-Synced Campus Reminders:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Syncing Gmail automatically extracts both Deadlines and Campus Schedule alerts (like Parcel timings, Paper Cribs, Copy Check, Shuttle, etc.). You can also add custom reminders with "+ Reminder".', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F221A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('About Green Board', style: TextStyle(fontSize: 16, color: Color(0xFF34D399))),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Green Board • B-School Workspace', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
            const SizedBox(height: 6),
            const Text('Version 2.7.0 (Hover Glow & Scale + Gmail Reminders + Particle Mesh)', style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 10),
            const Text('Built for B-School students to zero in on Placement Committee deadlines, surprise quizzes, case comps, and daily campus schedules.', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
            const SizedBox(height: 14),
            const Text('Created by _Bronkind_', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF34D399))),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => html.window.open('https://www.linkedin.com/in/bhanu-lohare/', '_blank'),
              child: const Text(
                'https://www.linkedin.com/in/bhanu-lohare/',
                style: TextStyle(fontSize: 12, color: Color(0xFF60A5FA), decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceBoxView() {
    final issueCtrl = TextEditingController();

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voice Box • Feedback & Suggestions',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFFECFDF5)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Facing any issues, automation errors, or want a new feature? Type below to send it directly to our Telegram.',
            style: TextStyle(fontSize: 12.5, color: Colors.white60),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: issueCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Type your feedback or issue here...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: HoverScaleGlow(
              scale: 1.06,
              glowColor: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(10),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: const Color(0xFF05110C),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final text = issueCtrl.text.trim();
                  if (text.isEmpty) return;

                  const botToken = '8844738614:AAFb1RNQ77e-6ub1OUBj--n6AQG0QXpOnuk';
                  const chatId = '1689696474';
                  final url = Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');

                  try {
                    final response = await http.post(
                      url,
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'chat_id': chatId,
                        'text': '🚨 New Green Board Feedback:\n\n$text',
                      }),
                    );

                    if (response.statusCode == 200) {
                      setState(() {
                        voiceBoxSubmissions.add({'text': text, 'time': 'Just now'});
                      });
                      issueCtrl.clear();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Feedback sent to Telegram!')),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.send_rounded, size: 15),
                label: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableDeadlinesView(List<DeadlineItem> items, bool isWideScreen) {
    if (items.isEmpty) {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        children: [
          const Text('On your radar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white54)),
          const SizedBox(height: 36),
          Center(
            child: Text(
              currentView == ViewMode.trash
                  ? 'Trash is empty'
                  : 'No upcoming deadlines right now! Tap Mail Sync or Link icon above.',
              style: const TextStyle(fontSize: 13, color: Colors.white38),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isWideScreen ? 20 : 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('On your radar', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white54)),
              if (showOnlyCritical)
                TextButton.icon(
                  onPressed: () => setState(() => showOnlyCritical = false),
                  icon: const Icon(Icons.clear, size: 13, color: Color(0xFFFBBF24)),
                  label: const Text('Clear Filter', style: TextStyle(fontSize: 11, color: Color(0xFFFBBF24))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              itemCount: items.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildFrostedCard(items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrostedCard(DeadlineItem item) {
    final urgencyColor = _getUrgencyColor(item.dueDate);
    final isTrash = currentView == ViewMode.trash;
    final isVeryImportant = item.importance == 'Very Important';

    return HoverScaleGlow(
      scale: 1.022,
      glowColor: urgencyColor,
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showEmailSummaryDialog(item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: urgencyColor.withValues(alpha: 0.45), width: 1.1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: urgencyColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_rounded, size: 11, color: urgencyColor),
                          const SizedBox(width: 4),
                          Text(
                            _formatRemainingTime(item.dueDate),
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: urgencyColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isVeryImportant
                            ? const Color(0xFFF43F5E).withValues(alpha: 0.15)
                            : const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isVeryImportant ? '🔥 URGENT' : '⚡ IMP',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: isVeryImportant ? const Color(0xFFFB7185) : const Color(0xFF34D399),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (isTrash) ...[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.restore_rounded, color: Color(0xFF34D399), size: 17),
                        onPressed: () => _restoreFromTrash(item),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFF43F5E), size: 17),
                        onPressed: () => _deletePermanently(item),
                      ),
                    ] else ...[
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: Checkbox(
                          value: item.isCompleted,
                          activeColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (val) => _toggleComplete(item, val),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 17),
                        onPressed: () => _moveToTrash(item),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  item.subCategory.toUpperCase(),
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.7, color: Colors.white54),
                ),
                const SizedBox(height: 2),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                    color: item.isCompleted ? Colors.white38 : const Color(0xFFF8FAFC),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item.category} • Due: ${item.dueDate.day}/${item.dueDate.month} ${item.dueDate.hour}:${item.dueDate.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 10.5, color: Colors.white38),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    HoverScaleGlow(
                      scale: 1.1,
                      glowColor: const Color(0xFF34D399),
                      borderRadius: BorderRadius.circular(8),
                      tooltip: 'Open Exact Mail in Gmail',
                      onTap: () => _openExactEmailById(item.gmailMessageId, item.title, item.source),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mail_outline_rounded, color: Color(0xFF34D399), size: 13),
                            SizedBox(width: 4),
                            Icon(Icons.open_in_new_rounded, color: Color(0xFF34D399), size: 11),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryView() {
    if (actionHistory.isEmpty) {
      return const Center(child: Text('No activity in last 24h', style: TextStyle(color: Colors.white54, fontSize: 13)));
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: actionHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = actionHistory[index];
        return HoverScaleGlow(
          scale: 1.015,
          glowColor: const Color(0xFF10B981),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          decoration: log.isReverted ? TextDecoration.lineThrough : null,
                          color: log.isReverted ? Colors.white38 : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${DateTime.now().difference(log.timestamp).inMinutes}m ago',
                        style: const TextStyle(fontSize: 10.5, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
                if (!log.isReverted)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFBBF24),
                      side: BorderSide(color: const Color(0xFFFBBF24).withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: () {
                      log.undoCallback();
                      setState(() => log.isReverted = true);
                    },
                    child: const Text('Undo', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showManualAddDialog() {
    final linkOrIdCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final snippetCtrl = TextEditingController();
    final subCatCtrl = TextEditingController(text: 'Action Item');
    String chosenCategory = categories[1];
    DateTime selectedDateTime = DateTime.now().add(const Duration(days: 1));
    bool isFetchingMail = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F221A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Deadline or Analyze Link', style: TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Paste Gmail Link / Message ID:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: linkOrIdCtrl,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: 'https://mail.google.com/...',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: isFetchingMail
                                  ? null
                                  : () async {
                                      final rawInput = linkOrIdCtrl.text.trim();
                                      if (rawInput.isEmpty) return;
                                      setDialogState(() => isFetchingMail = true);
                                      try {
                                        GoogleSignInAccount? account = _googleSignIn.currentUser;
                                        account ??= await _googleSignIn.signIn();
                                        if (account != null) {
                                          final authHeaders = await account.authHeaders;
                                          final gmailApi = gmail.GmailApi(GoogleAuthClient(authHeaders));
                                          final msgId = _extractMsgIdFromInput(rawInput);

                                          final msg = await gmailApi.users.messages.get('me', msgId, format: 'metadata', metadataHeaders: ['Subject', 'From']);
                                          String subj = '';
                                          String from = '';
                                          for (var h in msg.payload?.headers ?? []) {
                                            if (h.name?.toLowerCase() == 'subject') subj = h.value ?? '';
                                            if (h.name?.toLowerCase() == 'from') from = h.value ?? '';
                                          }
                                          final snip = msg.snippet ?? '';
                                          final autoCat = _autoClassifyEmail(subj, snip, from);
                                          final autoSub = _extractSubCategory('$subj $snip'.toLowerCase(), from.toLowerCase());
                                          final autoDate = _extractDueDateFromText(
                                            subject: subj,
                                            snippet: snip,
                                            emailSentDate: DateTime.now(),
                                          );

                                          setDialogState(() {
                                            titleCtrl.text = _cleanTitle(subj);
                                            snippetCtrl.text = snip;
                                            chosenCategory = categories.contains(autoCat) ? autoCat : categories[1];
                                            subCatCtrl.text = autoSub;
                                            if (autoDate != null) selectedDateTime = autoDate;
                                          });
                                        }
                                      } catch (_) {
                                      } finally {
                                        setDialogState(() => isFetchingMail = false);
                                      }
                                    },
                              child: Text(isFetchingMail ? '...' : 'Analyze', style: const TextStyle(fontSize: 11.5)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title / Subject')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: snippetCtrl,
                    decoration: const InputDecoration(labelText: 'Details / Snippet'),
                    onChanged: (val) {
                      final detected = _extractDueDateFromText(
                        subject: titleCtrl.text,
                        snippet: val,
                        emailSentDate: DateTime.now(),
                      );
                      if (detected != null) {
                        setDialogState(() => selectedDateTime = detected);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: chosenCategory,
                    dropdownColor: const Color(0xFF0F221A),
                    items: categories.where((c) => c != 'All').map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setDialogState(() => chosenCategory = v ?? chosenCategory),
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () {
                if (titleCtrl.text.isEmpty) return;
                final rawLink = linkOrIdCtrl.text.trim();
                final item = DeadlineItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleCtrl.text.trim(),
                  subtitle: snippetCtrl.text.trim().isNotEmpty ? snippetCtrl.text.trim() : 'Manual entry',
                  category: chosenCategory,
                  subCategory: subCatCtrl.text.trim(),
                  dueDate: selectedDateTime,
                  source: _googleSignIn.currentUser?.email ?? savedUserEmail ?? 'Manual',
                  gmailMessageId: rawLink.isNotEmpty ? rawLink : null,
                  importance: 'Very Important',
                );
                setState(() => deadlines.add(item));
                _saveDataToLocal();
                Navigator.pop(context);
              },
              child: const Text('Save', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSectionDialog() {
    final secCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F221A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('New Section', style: TextStyle(fontSize: 15)),
        content: TextField(controller: secCtrl, decoration: const InputDecoration(labelText: 'Section Name')),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              final name = secCtrl.text.trim();
              if (name.isNotEmpty && !categories.contains(name)) {
                setState(() {
                  categories.add(name);
                  selectedCategory = name;
                });
                _saveDataToLocal();
                Navigator.pop(context);
              }
            },
            child: const Text('Create', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class InteractiveParticleBackground extends StatefulWidget {
  final Widget child;
  const InteractiveParticleBackground({super.key, required this.child});

  @override
  State<InteractiveParticleBackground> createState() => _InteractiveParticleBackgroundState();
}

class _InteractiveParticleBackgroundState extends State<InteractiveParticleBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_BgNode> _nodes = [];
  Offset? _touchPoint;
  final Random _rnd = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    for (int i = 0; i < 45; i++) {
      _nodes.add(_BgNode(
        x: _rnd.nextDouble(),
        y: _rnd.nextDouble(),
        vx: (_rnd.nextDouble() - 0.5) * 0.0014,
        vy: (_rnd.nextDouble() - 0.5) * 0.0014,
        r: _rnd.nextDouble() * 2.2 + 1.2,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => setState(() => _touchPoint = e.localPosition),
      onPointerMove: (e) => setState(() => _touchPoint = e.localPosition),
      onPointerUp: (_) => setState(() => _touchPoint = null),
      child: MouseRegion(
        onHover: (e) => setState(() => _touchPoint = e.localPosition),
        onExit: (_) => setState(() => _touchPoint = null),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _ParticleMeshPainter(nodes: _nodes, pointer: _touchPoint),
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _BgNode {
  double x, y, vx, vy, r;
  _BgNode({required this.x, required this.y, required this.vx, required this.vy, required this.r});

  void step() {
    x += vx;
    y += vy;
    if (x < 0 || x > 1) vx = -vx;
    if (y < 0 || y > 1) vy = -vy;
  }
}

class _ParticleMeshPainter extends CustomPainter {
  final List<_BgNode> nodes;
  final Offset? pointer;

  _ParticleMeshPainter({required this.nodes, required this.pointer});

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = const Color(0xFF34D399).withValues(alpha: 0.45);
    final ambientLinePaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.08)
      ..strokeWidth = 0.8;

    final List<Offset> positions = [];
    for (var n in nodes) {
      n.step();
      final pos = Offset(n.x * size.width, n.y * size.height);
      positions.add(pos);
      canvas.drawCircle(pos, n.r, dotPaint);
    }

    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        if (d < 110) {
          canvas.drawLine(positions[i], positions[j], ambientLinePaint);
        }
      }
    }

    if (pointer != null) {
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.18),
            const Color(0xFF10B981).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: pointer!, radius: 160));
      canvas.drawCircle(pointer!, 160, glowPaint);

      for (var pos in positions) {
        final dist = (pos - pointer!).distance;
        if (dist < 170) {
          final alpha = ((1.0 - dist / 170) * 0.65).clamp(0.0, 1.0);
          final linePaint = Paint()
            ..color = const Color(0xFF34D399).withValues(alpha: alpha)
            ..strokeWidth = 1.3;
          canvas.drawLine(pos, pointer!, linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _UndoBarWidget extends StatefulWidget {
  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  const _UndoBarWidget({
    required this.message,
    required this.onUndo,
    required this.onDismiss,
  });

  @override
  State<_UndoBarWidget> createState() => _UndoBarWidgetState();
}

class _UndoBarWidgetState extends State<_UndoBarWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF11261E).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6), width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Color(0xFF34D399), size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFFBBF24)),
                      onPressed: widget.onUndo,
                      child: const Text('UNDO', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return LinearProgressIndicator(
                    value: 1.0 - _controller.value,
                    backgroundColor: Colors.white10,
                    color: const Color(0xFFFBBF24),
                    minHeight: 3,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}