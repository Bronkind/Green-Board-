import 'dart:async';
import 'dart:convert';
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
  final String importance; // 'Very Important' or 'Important'
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
  String _syncProgressText = 'Sync Gmail';
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
      if (_scrollController.offset > 50 && !_isScrolled) {
        setState(() => _isScrolled = true);
      } else if (_scrollController.offset <= 50 && _isScrolled) {
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

  void _openExactEmailInGmail(DeadlineItem item) {
    final msgId = item.gmailMessageId;
    final accountEmail = item.source.contains('@')
        ? item.source
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
      final encodedQuery = Uri.encodeComponent('subject:"${item.title}"');
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
      _syncProgressText = 'Connecting...';
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
          _syncProgressText = 'Sync Gmail';
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
                  ? 'First scan for ${account.email}: Running Deep Inbox Scan...'
                  : 'Quick syncing new & recent 30 mails for ${account.email}...',
            ),
          ),
        );
      }

      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      final gmailApi = gmail.GmailApi(authenticateClient);

      const String query = '-from:linkedin.com -from:insideiim.com -from:smule.com -category:social '
          '(deadline OR "application published" OR "application modified" OR "process update" OR shortlisted '
          'OR "batch meet" OR "mandatorily" OR "surprise quiz" OR "assessment form" OR "assigned reading" '
          'OR "interest form" OR "paper cribs" OR "endterm" OR "midterm" OR "scholarship" OR "nbfa" '
          'OR "submission" OR "submit" OR "round" OR "eod" OR "conclave" OR "case competition" OR "unstop")';

      List<gmail.Message> allFetchedSummaries = [];

      if (isFirstScanForAccount) {
        String? pageToken;
        int pagesScanned = 0;
        do {
          setState(() => _syncProgressText = 'Deep Scan p.${pagesScanned + 1}...');
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
        setState(() => _syncProgressText = 'Checking top 30...');
        final messagesResponse = await gmailApi.users.messages.list(
          'me',
          q: query,
          maxResults: 30,
        );
        if (messagesResponse.messages != null) {
          allFetchedSummaries.addAll(messagesResponse.messages!);
        }
      }

      List<Map<String, String>> rawEmails = [];
      int count = 0;

      for (var msgSummary in allFetchedSummaries) {
        if (msgSummary.id == null) continue;
        if (deadlines.any((d) => d.gmailMessageId == msgSummary.id || d.id == 'gmail_${msgSummary.id}')) {
          continue;
        }

        count++;
        if (mounted) {
          setState(() => _syncProgressText = 'Reading $count new...');
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

      if (!syncedAccounts.contains(account.email)) {
        syncedAccounts.add(account.email);
      }

      if (!mounted) return;

      final now = DateTime.now();
      setState(() {
        deadlines.removeWhere((d) => d.dueDate.isBefore(now) && !d.isCompleted);
        deadlines.addAll(newDeadlines);
      });
      await _saveDataToLocal();

      if (newDeadlines.isNotEmpty) {
        _recordAction(
          description: isFirstScanForAccount
              ? 'Deep synced ${newDeadlines.length} live deadlines (${account.email})'
              : 'Quick synced ${newDeadlines.length} new deadlines (${account.email})',
          actionType: 'sync',
          onUndo: () {
            setState(() {
              for (var item in newDeadlines) {
                deadlines.removeWhere((d) => d.id == item.id);
              }
            });
            _saveDataToLocal();
          },
        );
      } else if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFirstScanForAccount
                  ? 'Deep scan complete! No new unexpired deadlines found.'
                  : 'Checked recent 30 mails — you are all caught up!',
            ),
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
          _syncProgressText = 'Sync Gmail';
        });
      }
    }
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
    } else {
      setState(() {
        deadlines = [];
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
            const Icon(Icons.mail_rounded, color: Color(0xFF34D399), size: 20),
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
              _openExactEmailInGmail(item);
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('Open Exact Mail in Gmail', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              margin: EdgeInsets.all(isWideScreen ? 16 : 8),
              decoration: BoxDecoration(
                color: const Color(0xFF091610),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFF5A381E).withValues(alpha: 0.5),
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopHeader(isWideScreen),
                  if (currentView == ViewMode.board) ...[
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 250),
                      crossFadeState: _isScrolled ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                      firstChild: _buildHeroBanner(criticalCount),
                      secondChild: _buildShrunkenHeader(criticalCount),
                    ),
                    _buildCategoryFilterBar(),
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
            if (activeUndoToasts.isNotEmpty)
              Positioned(
                bottom: 24,
                left: 20,
                right: 20,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check_rounded, color: Color(0xFF34D399), size: 16),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GREEN BOARD',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 1.0,
                      color: Color(0xFFECFDF5),
                    ),
                  ),
                  Text(
                    'B-School Workspace',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: hasDoneDeepScan
                    ? 'Quick Scan: Checks new + recent 30 emails'
                    : 'First Scan: Runs full inbox deep scan',
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    foregroundColor: const Color(0xFFFBBF24),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                    ),
                  ),
                  onPressed: _isSyncing ? null : () => _handleGoogleGmailSync(isAuto: false),
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFBBF24)),
                        )
                      : const Icon(Icons.mail_outline_rounded, size: 15),
                  label: Text(
                    _isSyncing
                        ? _syncProgressText
                        : (hasDoneDeepScan ? 'Quick Sync (30)' : 'Sync Gmail'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              _buildLucidNavButton(
                label: 'Board',
                icon: Icons.dashboard_rounded,
                isActive: currentView == ViewMode.board,
                onTap: () => setState(() => currentView = ViewMode.board),
              ),
              _buildLucidNavButton(
                label: '24h History ($historyCount)',
                icon: Icons.history_rounded,
                isActive: currentView == ViewMode.history,
                onTap: () => setState(() => currentView = ViewMode.history),
              ),
              _buildLucidNavButton(
                label: 'Trash ($trashCount)',
                icon: Icons.delete_outline_rounded,
                isActive: currentView == ViewMode.trash,
                onTap: () => setState(() => currentView = ViewMode.trash),
              ),
              _buildLucidNavButton(
                label: 'Voice Box',
                icon: Icons.chat_bubble_outline_rounded,
                isActive: currentView == ViewMode.feedback,
                onTap: () => setState(() => currentView = ViewMode.feedback),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                offset: const Offset(0, 45),
                color: const Color(0xFF0F221A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Active Account', style: TextStyle(fontSize: 11, color: Colors.white54)),
                        const SizedBox(height: 2),
                        Text(
                          currentUserName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                        ),
                        Text(
                          currentUserEmail,
                          style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (syncedAccounts.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Synced IDs: ${syncedAccounts.length}',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFFFBBF24)),
                          ),
                        ],
                        const Divider(color: Colors.white24, height: 16),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'switch_account',
                    child: Row(
                      children: [
                        Icon(Icons.person_add_alt_1_rounded, size: 16, color: Color(0xFFFBBF24)),
                        SizedBox(width: 10),
                        Text('Sync Another Gmail ID', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'force_deep_scan',
                    child: Row(
                      children: [
                        Icon(Icons.radar_rounded, size: 16, color: Color(0xFF34D399)),
                        SizedBox(width: 10),
                        Text('Force Full Deep Scan', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'how_to_use',
                    child: Row(
                      children: [
                        Icon(Icons.help_outline_rounded, size: 16, color: Color(0xFF34D399)),
                        SizedBox(width: 10),
                        Text('How to Use', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'about',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF34D399)),
                        SizedBox(width: 10),
                        Text('About Green Board', style: TextStyle(fontSize: 13)),
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
                        Text('Logout', style: TextStyle(fontSize: 13, color: Color(0xFFF43F5E))),
                      ],
                    ),
                  ),
                ],
                onSelected: (String value) {
                  if (value == 'switch_account') {
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 18),
                    ],
                  ),
                ),
              ),
            ],
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
              Text('1. Smart Two-Stage Sync:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              Text('First login performs a Deep Inbox Scan. Every subsequent sync ("Quick Sync (30)") only checks new + recent 30 emails for instant speed.', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
              SizedBox(height: 10),
              Text('2. Instant Persistent Storage:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Close the browser window anytime—when you reopen Green Board, all your previously synced deadlines load immediately.', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
              SizedBox(height: 10),
              Text('3. Direct Open & Link Analyzer:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Click "Open Mail ↗" on any card to open that exact email in Gmail, or use "+ Add / Link" to fetch any missed email by URL/ID.', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
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
            const Text('Version 2.2.0 (Persistent + Quick-Sync Engine)', style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 10),
            const Text('Built for B-School students to zero in on Placement Committee deadlines, surprise quizzes, case comps, and scholarships without inbox clutter.', style: TextStyle(fontSize: 12.5, color: Colors.white70)),
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

  Widget _buildLucidNavButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? const Color(0xFF34D399) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isActive ? const Color(0xFF34D399) : Colors.white70),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? const Color(0xFFECFDF5) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner(int criticalCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'B-SCHOOL WORKSPACE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.45)),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: Color(0xFFF1F5F9), fontFamily: 'Georgia'),
                    children: [
                      TextSpan(text: 'Your deadlines, '),
                      TextSpan(
                        text: 'under control.',
                        style: TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF34D399), fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Spam-free live deadlines calibrated for Placements, Acads & Case Comps.',
                  style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                showOnlyCritical = !showOnlyCritical;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: showOnlyCritical ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: showOnlyCritical ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFBBF24), size: 16),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FOCUS WINDOW', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFFFBBF24))),
                      const SizedBox(height: 2),
                      Text('$criticalCount critical', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShrunkenHeader(int criticalCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text(
                'Deadlines, under control.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF34D399), fontFamily: 'Georgia', fontStyle: FontStyle.italic),
              ),
              const SizedBox(width: 12),
              Text(
                '•  B-School Workspace',
                style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.45)),
              ),
            ],
          ),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                showOnlyCritical = !showOnlyCritical;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: showOnlyCritical ? const Color(0xFFF59E0B).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFBBF24), size: 14),
                  const SizedBox(width: 6),
                  Text('$criticalCount critical', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...categories.map((cat) {
                    bool isSelected = selectedCategory == cat && !showOnlyCritical;
                    final count = cat == 'All'
                        ? deadlines.where((d) => !d.isDeleted && !d.isCompleted).length
                        : deadlines.where((d) => !d.isDeleted && !d.isCompleted && d.category == cat).length;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => setState(() {
                          selectedCategory = cat;
                          showOnlyCritical = false;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF10B981) : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF34D399) : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF05110C) : Colors.white,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 11,
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
          const SizedBox(width: 12),
          ActionChip(
            avatar: const Icon(Icons.add, size: 14, color: Color(0xFF34D399)),
            label: const Text('Section', style: TextStyle(fontSize: 12)),
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            side: BorderSide(color: const Color(0xFF34D399).withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            onPressed: _showAddSectionDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCompletedTabs(int pendingCount, int completedCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 240,
            height: 38,
            color: Colors.transparent,
            child: TabBar(
              controller: _statusTabController,
              indicatorColor: const Color(0xFF10B981),
              labelColor: const Color(0xFF34D399),
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              tabs: [
                Tab(text: 'Pending  $pendingCount'),
                Tab(text: 'Completed  $completedCount'),
              ],
            ),
          ),
          Row(
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Saved Locally', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.45))),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                ),
                onPressed: _showManualAddDialog,
                icon: const Icon(Icons.add_link_rounded, size: 15, color: Color(0xFF34D399)),
                label: const Text('Add / Link', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceBoxView() {
    final issueCtrl = TextEditingController();

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voice Box • Feedback & Suggestions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFECFDF5)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Facing any issues, automation errors, or want a new feature? Type below to send it directly to our Telegram.',
            style: TextStyle(fontSize: 13, color: Colors.white60),
          ),
          const SizedBox(height: 16),
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
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: const Color(0xFF05110C),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Feedback successfully sent to Telegram!')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to send, please try again.')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Send Message', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableDeadlinesView(List<DeadlineItem> items, bool isWideScreen) {
    if (items.isEmpty) {
      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('On your radar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white54)),
            const SizedBox(height: 40),
            Center(
              child: Text(
                currentView == ViewMode.trash
                    ? 'Trash is empty'
                    : 'No upcoming deadlines right now! Click "Sync Gmail" or "+ Add / Link".',
                style: const TextStyle(fontSize: 14, color: Colors.white38),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('On your radar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white54)),
              if (showOnlyCritical)
                TextButton.icon(
                  onPressed: () => setState(() => showOnlyCritical = false),
                  icon: const Icon(Icons.clear, size: 14, color: Color(0xFFFBBF24)),
                  label: const Text('Clear Filter', style: TextStyle(fontSize: 12, color: Color(0xFFFBBF24))),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
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

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showEmailSummaryDialog(item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: urgencyColor.withValues(alpha: 0.45), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: urgencyColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_rounded, size: 12, color: urgencyColor),
                          const SizedBox(width: 5),
                          Text(
                            _formatRemainingTime(item.dueDate),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: urgencyColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isVeryImportant
                            ? const Color(0xFFF43F5E).withValues(alpha: 0.15)
                            : const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isVeryImportant ? '🔥 VERY IMPORTANT' : '⚡ IMPORTANT',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: isVeryImportant ? const Color(0xFFFB7185) : const Color(0xFF34D399),
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (isTrash) ...[
                      IconButton(
                        icon: const Icon(Icons.restore_rounded, color: Color(0xFF34D399), size: 18),
                        onPressed: () => _restoreFromTrash(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever_rounded, color: Color(0xFFF43F5E), size: 18),
                        onPressed: () => _deletePermanently(item),
                      ),
                    ] else ...[
                      Checkbox(
                        value: item.isCompleted,
                        activeColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          _toggleComplete(item, val);
                          setState(() {});
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 18),
                        onPressed: () => _moveToTrash(item),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.subCategory.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Colors.white54),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
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
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item.category}  •  Due: ${item.dueDate.day}/${item.dueDate.month} ${item.dueDate.hour}:${item.dueDate.minute.toString().padLeft(2, '0')}  •  ${item.source}',
                        style: const TextStyle(fontSize: 11, color: Colors.white38),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _openExactEmailInGmail(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mail_outline_rounded, color: Color(0xFF34D399), size: 13),
                            SizedBox(width: 5),
                            Text(
                              'Open Mail',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF34D399),
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.open_in_new_rounded, color: Color(0xFF34D399), size: 12),
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
      padding: const EdgeInsets.all(24),
      itemCount: actionHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final log = actionHistory[index];
        return Container(
          padding: const EdgeInsets.all(14),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: log.isReverted ? TextDecoration.lineThrough : null,
                        color: log.isReverted ? Colors.white38 : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${DateTime.now().difference(log.timestamp).inMinutes}m ago',
                      style: const TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              if (log.id != 'init-log' && !log.isReverted)
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
          title: const Text('Add Deadline or Analyze Gmail Link', style: TextStyle(fontSize: 16)),
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
                          'Missed an email? Paste Gmail Link / Message ID:',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: linkOrIdCtrl,
                                style: const TextStyle(fontSize: 12.5),
                                decoration: const InputDecoration(
                                  hintText: 'https://mail.google.com/... or Message ID',
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
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Link saved! Now enter/paste the subject or snippet below to auto-detect date.')),
                                          );
                                        }
                                      } finally {
                                        setDialogState(() => isFetchingMail = false);
                                      }
                                    },
                              child: Text(isFetchingMail ? '...' : 'Analyze', style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title / Email Subject')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: snippetCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email Snippet / Details (Paste text to auto-detect date)',
                    ),
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
                  const SizedBox(height: 10),
                  TextField(controller: subCatCtrl, decoration: const InputDecoration(labelText: 'Sub-Category / Round')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: chosenCategory,
                    dropdownColor: const Color(0xFF0F221A),
                    items: categories.where((c) => c != 'All').map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setDialogState(() => chosenCategory = v ?? chosenCategory),
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Due: ${selectedDateTime.day}/${selectedDateTime.month}/${selectedDateTime.year} at ${selectedDateTime.hour}:${selectedDateTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF34D399), fontWeight: FontWeight.w600),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF34D399),
                          side: BorderSide(color: const Color(0xFF34D399).withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: selectedDateTime,
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (pickedDate != null) {
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                            );
                            if (pickedTime != null) {
                              setDialogState(() {
                                selectedDateTime = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                );
                              });
                            }
                          }
                        },
                        child: const Text('Pick Date/Time', style: TextStyle(fontSize: 11)),
                      ),
                    ],
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
                String sourceTag = _googleSignIn.currentUser?.email ?? savedUserEmail ?? (rawLink.isNotEmpty ? 'Analyzed Link' : 'Manual');
                String subtitleText = snippetCtrl.text.trim().isNotEmpty
                    ? snippetCtrl.text.trim()
                    : (rawLink.isNotEmpty ? 'Linked Mail Reference' : 'Manual entry');

                final item = DeadlineItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleCtrl.text.trim(),
                  subtitle: subtitleText,
                  category: chosenCategory,
                  subCategory: subCatCtrl.text.trim().isEmpty ? 'General' : subCatCtrl.text.trim(),
                  dueDate: selectedDateTime,
                  source: sourceTag,
                  gmailMessageId: rawLink.isNotEmpty ? rawLink : null,
                  importance: 'Very Important',
                );
                setState(() => deadlines.add(item));
                _saveDataToLocal();
                Navigator.pop(context);
                _recordAction(
                  description: 'Added "${item.title}"',
                  actionType: 'add',
                  onUndo: () {
                    setState(() => deadlines.remove(item));
                    _saveDataToLocal();
                  },
                );
              },
              child: const Text('Save Deadline', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
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
        title: const Text('New Section', style: TextStyle(fontSize: 16)),
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
                _recordAction(
                  description: 'Created section "$name"',
                  actionType: 'section',
                  onUndo: () {
                    setState(() {
                      categories.remove(name);
                      if (selectedCategory == name) selectedCategory = 'All';
                    });
                    _saveDataToLocal();
                  },
                );
              }
            },
            child: const Text('Create', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 250),
      builder: (context, val, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - val)),
          child: Opacity(
            opacity: val,
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF11261E).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Color(0xFF34D399), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFFBBF24)),
                        onPressed: widget.onUndo,
                        child: const Text('UNDO', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
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
      ),
    );
  }
}