import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

import 'api_client.dart';
import 'premium_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const BookApp());

class Book {
  const Book({
    required this.id,
    required this.backendId,
    required this.titleMy,
    required this.titleEn,
    required this.author,
    required this.description,
    required this.color,
  });
  final String id, titleMy, titleEn, author, description;
  final int backendId;
  final Color color;

  factory Book.fromApi(Map<String, dynamic> json, Color color) {
    final rawId = json['id'];
    return Book(
      id: json['slug']?.toString() ?? 'book-$rawId',
      backendId: rawId is int ? rawId : int.tryParse('$rawId') ?? 0,
      titleMy: json['titleMy']?.toString() ?? 'မြန်မာစာအုပ်',
      titleEn: json['titleEn']?.toString() ?? 'Untitled book',
      author: json['author']?.toString() ?? 'Unknown author',
      description: json['description']?.toString() ?? '',
      color: color,
    );
  }

  String title(Locale locale) =>
      locale.languageCode == 'my' ? titleMy : titleEn;
}

class ConversionJob {
  ConversionJob(this.filename);
  final String filename;
  String? remoteId;
  String status = 'Queued';
  String? error;
}

class AppState extends ChangeNotifier {
  Locale locale = const Locale('my');
  ThemeMode themeMode = ThemeMode.system;
  bool isPremium = false, isAdmin = false, isSignedIn = false;
  bool _localeChanged = false, _themeChanged = false;
  int tabIndex = 0;
  bool catalogLoading = false;
  String? catalogError;
  final jobs = <ConversionJob>[];
  final readingProgress = <String, int>{};
  final readingBookmarks = <String, Set<int>>{};
  final bookmarkIds = <String, Map<int, String>>{};
  final ApiClient api = ApiClient();
  final PremiumPurchaseService purchaseService = PremiumPurchaseService();
  List<ProductDetails> premiumProducts = [];
  String? userName, userEmail, sessionError;
  Map<String, dynamic>? subscription;
  bool sessionLoading = false,
      purchaseLoading = false,
      accountActionLoading = false;
  final books = <Book>[
    Book(
      id: 'midnight-river',
      backendId: 1,
      titleMy: 'ညသန်းခေါင်က မြစ်',
      titleEn: 'The Midnight River',
      author: 'Aye Thiri',
      description: 'A quiet novel about memory, distance, and the choices that bring people home.',
      color: Color(0xff6d5dfc),
    ),
    Book(
      id: 'rain-letter',
      backendId: 2,
      titleMy: 'မိုးရေစက်စာ',
      titleEn: 'Letters in the Rain',
      author: 'Min Thu',
      description: 'Two unfinished letters become a journey through Yangon, Mandalay, and old promises.',
      color: Color(0xffd46b4c),
    ),
    Book(
      id: 'last-lantern',
      backendId: 3,
      titleMy: 'နောက်ဆုံးမီးအိမ်',
      titleEn: 'The Last Lantern',
      author: 'Su Myat',
      description:
          'A warm story of a small bookstore and the people who find it.',
      color: Color(0xff238b8b),
    ),
  ];

  AppState() {
    _load();
    _restoreSession();
    loadCatalog();
    initializePurchases();
  }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!_localeChanged) {
      locale = Locale(p.getString('locale') ?? 'my');
    }
    if (!_themeChanged) {
      themeMode = ThemeMode.values.firstWhere(
        (x) => x.name == (p.getString('theme') ?? 'system'),
        orElse: () => ThemeMode.system,
      );
    }
    notifyListeners();
  }

  Future<void> loadCatalog() async {
    catalogLoading = true;
    notifyListeners();
    try {
      final body = await api.catalog().timeout(const Duration(seconds: 3));
      final remote = (body['books'] as List?)
          ?.whereType<Map>()
          .map((json) => json.cast<String, dynamic>())
          .toList();
      if (remote != null && remote.isNotEmpty) {
        const colors = [
          Color(0xff6d5dfc),
          Color(0xffd46b4c),
          Color(0xff238b8b),
        ];
        books
          ..clear()
          ..addAll(
            List.generate(
              remote.length,
              (index) =>
                  Book.fromApi(remote[index], colors[index % colors.length]),
            ),
          );
      }
      catalogError = null;
    } catch (error) {
      catalogError = error.toString();
    } finally {
      catalogLoading = false;
      notifyListeners();
    }
  }

  Future<void> initializePurchases() async {
    try {
      if (!await purchaseService.isAvailable()) return;
      premiumProducts = await purchaseService.loadProducts();
      purchaseService.listen(onPurchase: _handlePurchase);
      notifyListeners();
    } catch (error) {
      sessionError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.pending) {
      purchaseLoading = true;
      notifyListeners();
      return;
    }
    if (purchase.status == PurchaseStatus.error) {
      purchaseLoading = false;
      sessionError = purchase.error?.message ?? 'Purchase failed';
      notifyListeners();
      return;
    }
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      if (!isSignedIn || !api.hasSession) {
        sessionError = 'Sign in is required before verifying a purchase';
      } else {
        try {
          final platform = defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android';
          final verified = await api.verifyPurchase(
            platform: platform,
            productId: purchase.productID,
            purchaseToken: purchase.verificationData.serverVerificationData,
          );
          isPremium =
              verified['status'] == 'active' || verified['entitlement'] != null;
          sessionError = null;
        } catch (error) {
          sessionError = error.toString();
        }
      }
    }
    purchaseLoading = false;
    notifyListeners();
  }

  Future<void> buyPremium(ProductDetails product) async {
    if (!isSignedIn) {
      sessionError = 'Sign in is required before purchasing Premium';
      notifyListeners();
      return;
    }
    purchaseLoading = true;
    notifyListeners();
    try {
      await purchaseService.start(product);
    } catch (error) {
      purchaseLoading = false;
      sessionError = error.toString();
      notifyListeners();
    }
  }

  Future<void> restorePremium() async {
    purchaseLoading = true;
    sessionError = null;
    notifyListeners();
    try {
      await purchaseService.restore();
    } catch (error) {
      purchaseLoading = false;
      sessionError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _restoreSession() async {
    // Tokens intentionally remain memory-only until a platform secure-storage
    // implementation is selected for the target release configuration.
    api.clearSession();
  }

  Future<bool> loginDemo({required bool admin}) async {
    sessionLoading = true;
    sessionError = null;
    notifyListeners();
    try {
      final body = await api.demoAuth(
        role: admin ? 'admin' : 'user',
        name: admin ? 'Admin Account' : 'Reader Account',
      );
      final token = body['token']?.toString();
      if (token == null || token.isEmpty) {
        throw StateError('Missing session token');
      }
      api.setToken(token);
      final user = (body['user'] as Map?)?.cast<String, dynamic>();
      isSignedIn = true;
      isAdmin = user?['role'] == 'admin';
      userName = user?['name']?.toString();
      userEmail = user?['email']?.toString();
      await loadSubscription();
      return true;
    } catch (error) {
      sessionError = error.toString();
      return false;
    } finally {
      sessionLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSubscription() async {
    if (!isSignedIn || !api.hasSession) return;
    try {
      subscription = await api.subscriptionStatus();
      isPremium = subscription?['isPremium'] == true;
      sessionError = null;
      notifyListeners();
    } catch (error) {
      sessionError = error.toString();
      notifyListeners();
    }
  }

  Future<bool> requestAccountDeletion() async {
    if (!isSignedIn || !api.hasSession) return false;
    accountActionLoading = true;
    sessionError = null;
    notifyListeners();
    try {
      await api.requestAccountDeletion();
      return true;
    } catch (error) {
      sessionError = error.toString();
      return false;
    } finally {
      accountActionLoading = false;
      notifyListeners();
    }
  }

  Future<String?> requestPasswordReset(String email) async {
    try {
      await api.requestPasswordReset(email);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  Future<bool> activateDemoPremium() async {
    if (!isSignedIn || !api.hasSession) return false;
    try {
      final body = await api.activateDemoPremium();
      isPremium = body['status'] == 'active';
      sessionError = null;
      notifyListeners();
      return isPremium;
    } catch (error) {
      sessionError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> toggleLocale() async {
    _localeChanged = true;
    locale = Locale(locale.languageCode == 'my' ? 'en' : 'my');
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('locale', locale.languageCode);
  }

  Future<void> cycleTheme() async {
    _themeChanged = true;
    themeMode = switch (themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', themeMode.name);
  }

  void signIn({bool admin = false}) {
    isSignedIn = true;
    isAdmin = admin;
    notifyListeners();
  }

  void signOut() {
    isSignedIn = false;
    isAdmin = false;
    isPremium = false;
    userName = null;
    userEmail = null;
    subscription = null;
    sessionError = null;
    tabIndex = 0;
    api.clearSession();
    notifyListeners();
  }

  void unlockDemo() {
    isSignedIn = true;
    isPremium = true;
    notifyListeners();
  }

  void setTab(int index) {
    tabIndex = index;
    notifyListeners();
  }

  void setProgress(String bookId, int page) {
    readingProgress[bookId] = page;
    notifyListeners();
  }

  Future<bool> canReadFull(Book book) async {
    if (!isSignedIn || !api.hasSession) return false;
    try {
      final body = await api.fullBookAccess(book.backendId);
      return body['access'] == 'full';
    } catch (error) {
      sessionError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<File?> cachedBookFile(Book book) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/book_cache/${book.id}.pdf');
    if (await file.exists() && await file.length() > 0) return file;
    return null;
  }

  Future<File> prepareProtectedPdf(Book book) async {
    final cached = await cachedBookFile(book);
    if (cached != null) return cached;
    if (!await canReadFull(book)) {
      throw StateError('Premium entitlement required');
    }
    final bytes = await api.downloadProtectedBook(book.backendId);
    if (bytes.isEmpty) throw StateError('The protected PDF is empty');
    final directory = await getApplicationDocumentsDirectory();
    final cacheDirectory = Directory('${directory.path}/book_cache');
    await cacheDirectory.create(recursive: true);
    final file = File('${cacheDirectory.path}/${book.id}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> syncProgress(Book book, int page, int totalPages) async {
    setProgress(book.id, page);
    if (!isSignedIn || !api.hasSession) return;
    try {
      await api.saveProgress(
        bookId: book.backendId,
        pageNumber: page,
        percent: ((page / totalPages) * 100).round().clamp(0, 100),
      );
    } catch (error) {
      sessionError = error.toString();
      notifyListeners();
    }
  }

  Future<void> loadBookmarks(Book book) async {
    if (!isSignedIn || !api.hasSession) return;
    try {
      final body = await api.getBookmarks(book.backendId);
      final items =
          (body['bookmarks'] as List?)?.whereType<Map>().toList() ?? [];
      readingBookmarks[book.id] = items
          .map((item) => (item['pageNumber'] as num).toInt())
          .toSet();
      bookmarkIds[book.id] = {
        for (final item in items)
          (item['pageNumber'] as num).toInt(): item['id'].toString(),
      };
      notifyListeners();
    } catch (error) {
      sessionError = error.toString();
      notifyListeners();
    }
  }

  Future<bool> toggleBookmark(Book book, int page) async {
    final pages = readingBookmarks.putIfAbsent(book.id, () => <int>{});
    final ids = bookmarkIds.putIfAbsent(book.id, () => <int, String>{});
    try {
      if (pages.contains(page)) {
        final id = ids[page];
        if (id != null && isSignedIn && api.hasSession) {
          await api.deleteBookmark(bookId: book.backendId, bookmarkId: id);
        }
        pages.remove(page);
        ids.remove(page);
      } else {
        pages.add(page);
        if (isSignedIn && api.hasSession) {
          final body = await api.addBookmark(
            bookId: book.backendId,
            pageNumber: page,
          );
          final bookmark = (body['bookmark'] as Map?)?.cast<String, dynamic>();
          final id = bookmark?['id']?.toString();
          if (id != null) ids[page] = id;
        }
      }
      notifyListeners();
      return true;
    } catch (error) {
      sessionError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    final job = ConversionJob(file.name);
    jobs.insert(0, job);
    notifyListeners();

    if (isAdmin && api.hasSession && bytes.isNotEmpty) {
      try {
        final body = await api.uploadBook(
          bookId: books.first.backendId,
          filename: file.name,
          bytes: bytes,
        );
        final remote = (body['job'] as Map?)?.cast<String, dynamic>();
        job.remoteId = remote?['id']?.toString();
        job.status = _jobLabel(remote?['status']?.toString() ?? 'queued');
      } catch (error) {
        job.status = 'Failed';
        job.error = error.toString();
        sessionError = error.toString();
      }
      notifyListeners();
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 700));
    job.status = file.name.toLowerCase().endsWith('.epub')
        ? 'Converting'
        : 'Ready';
    notifyListeners();
    if (job.status == 'Converting') {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      job.status = 'Completed';
      notifyListeners();
    }
  }

  String _jobLabel(String value) => switch (value) {
    'processing' => 'Processing',
    'completed' => 'Completed',
    'failed' => 'Failed',
    _ => 'Queued',
  };

  Future<void> refreshAdminJobs() async {
    if (!isAdmin || !api.hasSession) return;
    try {
      final body = await api.adminJobs();
      final remote = (body['jobs'] as List?)?.whereType<Map>().toList() ?? [];
      jobs
        ..clear()
        ..addAll(
          remote.map((item) {
            final job = ConversionJob(
              item['sourceFilename']?.toString() ?? 'Book job',
            );
            job.remoteId = item['id']?.toString();
            job.status = _jobLabel(item['status']?.toString() ?? 'queued');
            job.error = item['errorMessage']?.toString();
            return job;
          }),
        );
      notifyListeners();
    } catch (error) {
      sessionError = error.toString();
      notifyListeners();
    }
  }

  Future<bool> publishBook(Book book) async {
    if (!isAdmin || !api.hasSession) return false;
    try {
      await api.publishBook(book.backendId);
      sessionError = null;
      notifyListeners();
      return true;
    } catch (error) {
      sessionError = error.toString();
      notifyListeners();
      return false;
    }
  }
}

class BookApp extends StatefulWidget {
  const BookApp({super.key});
  @override
  State<BookApp> createState() => _BookAppState();
}

class _BookAppState extends State<BookApp> {
  final state = AppState();
  @override
  void dispose() {
    state.purchaseService.dispose();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'စာအုပ်တိုက်',
      themeMode: state.themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: Shell(state: state),
    ),
  );
  ThemeData _theme(Brightness b) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff6d5dfc),
      brightness: b,
    ),
    scaffoldBackgroundColor: b == Brightness.dark
        ? const Color(0xff101114)
        : const Color(0xfffaf9fd),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}

String t(AppState s, String my, String en) =>
    s.locale.languageCode == 'my' ? my : en;

class Shell extends StatelessWidget {
  const Shell({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(state: state),
      CatalogPage(state: state),
      PremiumPage(state: state),
      ProfilePage(state: state),
      if (state.isAdmin) AdminPage(state: state),
    ];
    final index = state.tabIndex.clamp(0, pages.length - 1);
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          state.setTab(i);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: t(state, 'ပင်မ', 'Home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: t(state, 'စာအုပ်များ', 'Books'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.workspace_premium_outlined),
            selectedIcon: const Icon(Icons.workspace_premium),
            label: 'Premium',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: t(state, 'အကောင့်', 'Profile'),
          ),
          if (state.isAdmin)
            NavigationDestination(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: const Icon(Icons.admin_panel_settings),
              label: t(state, 'စီမံခန့်ခွဲ', 'Admin'),
            ),
        ],
      ),
    );
  }
}

class Frame extends StatelessWidget {
  const Frame({
    required this.state,
    required this.title,
    required this.child,
    super.key,
  });
  final AppState state;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              onPressed: state.toggleLocale,
              icon: const Icon(Icons.translate),
            ),
            IconButton(
              onPressed: state.cycleTheme,
              icon: Icon(
                state.themeMode == ThemeMode.dark
                    ? Icons.light_mode
                    : Icons.dark_mode,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) => Frame(
    state: state,
    title: t(state, 'စာအုပ်တိုက်', 'Book House'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              colors: [Color(0xff312e81), Color(0xff6d5dfc), Color(0xffc084fc)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_stories, color: Colors.white, size: 34),
              const SizedBox(height: 18),
              Text(
                t(
                  state,
                  'သင့်နောက်စာမျက်နှာကို ရှာဖွေပါ',
                  'Find your next chapter',
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                t(
                  state,
                  'မြန်မာနှင့် အင်္ဂလိပ်စာအုပ်များကို တစ်နေရာတည်းမှာ ဖတ်ရှုပါ။',
                  'Read Myanmar and English books in one calm place.',
                ),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.tonal(
                onPressed: () {
                  state.setTab(1);
                },
                child: Text(t(state, 'စာအုပ်များကြည့်ရန်', 'Browse books')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          t(state, 'ရွေးချယ်ထားသောစာအုပ်များ', 'Curated for your next read'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: state.books.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, i) =>
                BookCard(book: state.books[i], state: state, compact: true),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.workspace_premium,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              t(
                state,
                'Premium ဖြင့် အပြည့်အစုံဖတ်ရှုပါ',
                'Unlock every story with Premium',
              ),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              t(
                state,
                'စာအုပ်တိုင်းကို အကန့်အသတ်မရှိ ဖတ်ရှုနိုင်ပါသည်။',
                'Unlimited access to the full collection.',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class CatalogPage extends StatefulWidget {
  const CatalogPage({required this.state, super.key});
  final AppState state;
  @override
  State<CatalogPage> createState() => _CatalogState();
}

class _CatalogState extends State<CatalogPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final books = widget.state.books
        .where(
          (b) => '${b.titleMy} ${b.titleEn} ${b.author}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return Frame(
      state: widget.state,
      title: t(widget.state, 'စာအုပ်များ', 'Library'),
      child: Column(
        children: [
          if (widget.state.catalogLoading) const LinearProgressIndicator(),
          if (widget.state.catalogError != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off),
                title: Text(
                  t(widget.state, 'အင်တာနက်မရသေးပါ', 'Offline fallback'),
                ),
                subtitle: Text(
                  t(
                    widget.state,
                    'သိမ်းထားသောစာအုပ်များကို ပြသနေပါသည်။',
                    'Showing the locally cached catalog.',
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: widget.state.loadCatalog,
                ),
              ),
            ),
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: t(widget.state, 'စာအုပ်ရှာရန်', 'Search books'),
            ),
          ),
          const SizedBox(height: 18),
          ...books.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: BookCard(book: b, state: widget.state),
            ),
          ),
        ],
      ),
    );
  }
}

class BookCard extends StatelessWidget {
  const BookCard({
    required this.book,
    required this.state,
    this.compact = false,
    super.key,
  });
  final Book book;
  final AppState state;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailPage(book: book, state: state),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: compact ? 100 : 84,
                height: compact ? 145 : 114,
                decoration: BoxDecoration(
                  color: book.color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Icon(Icons.menu_book, color: Colors.white, size: 42),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      book.title(state.locale),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      book.author,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 8),
                      Text(
                        book.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    _badge(context, t(state, 'Preview', 'Preview')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return compact ? SizedBox(width: 290, child: card) : card;
  }

  Widget _badge(BuildContext c, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(c).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class DetailPage extends StatelessWidget {
  const DetailPage({required this.book, required this.state, super.key});
  final Book book;
  final AppState state;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t(state, 'စာအုပ်အသေးစိတ်', 'Book details'))),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 170,
                height: 240,
                decoration: BoxDecoration(
                  color: book.color,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.auto_stories,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              book.title(state.locale),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28),
            ),
            const SizedBox(height: 6),
            Text(
              book.author,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              book.description,
              style: const TextStyle(height: 1.5, fontSize: 16),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ReaderPage(book: book, state: state, preview: true),
                      ),
                    ),
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(t(state, 'နမူနာဖတ်ရန်', 'Read preview')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      try {
                        final file = await state.prepareProtectedPdf(book);
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PdfReaderPage(
                              book: book,
                              state: state,
                              file: file,
                            ),
                          ),
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        state.setTab(state.isSignedIn ? 2 : 3);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              state.isSignedIn
                                  ? t(
                                      state,
                                      'Premium လိုအပ်ပါသည်',
                                      'Premium access is required',
                                    )
                                  : t(
                                      state,
                                      'အရင်ဆုံး အကောင့်ဝင်ပါ',
                                      'Sign in first',
                                    ),
                            ),
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      state.isPremium
                          ? Icons.menu_book
                          : Icons.workspace_premium,
                    ),
                    label: Text(
                      state.isPremium
                          ? t(state, 'ဖတ်ရှုရန်', 'Read now')
                          : t(state, 'Premium ဝယ်ရန်', 'Get Premium'),
                    ),
                  ),
                ),
              ],
            ),
            if (!state.isPremium)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  t(
                    state,
                    'Preview ကိုအခမဲ့ကြည့်နိုင်ပြီး စာအုပ်အပြည့်အစုံအတွက် Premium လိုအပ်ပါသည်။',
                    'Preview is free; Premium unlocks the full book.',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    required this.book,
    required this.state,
    required this.preview,
    super.key,
  });
  final Book book;
  final AppState state;
  final bool preview;
  @override
  State<ReaderPage> createState() => _ReaderState();
}

class _ReaderState extends State<ReaderPage> {
  int page = 1;

  @override
  void initState() {
    super.initState();
    page = widget.state.readingProgress[widget.book.id] ?? 1;
    widget.state.loadBookmarks(widget.book);
  }

  void _goTo(int nextPage) {
    setState(() => page = nextPage);
    widget.state.syncProgress(
      widget.book,
      page,
      widget.preview ? 2 : pages.length,
    );
  }

  final pages = const [
    'Chapter One\n\nThe city was quiet after the rain. Between the old tea shop and the narrow lane, a single light remained awake.',
    'The letter had no address. Only a name, written carefully in blue ink, and a date from many years ago.',
    'Some stories begin when we stop looking for an ending. This one began with a book left open on a windowsill.',
  ];
  @override
  Widget build(BuildContext context) {
    final max = widget.preview ? 2 : pages.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title(widget.state.locale)),
        actions: [
          AnimatedBuilder(
            animation: widget.state,
            builder: (context, _) {
              final bookmarked =
                  widget.state.readingBookmarks[widget.book.id]?.contains(
                    page,
                  ) ==
                  true;
              return IconButton(
                onPressed: () async {
                  await widget.state.toggleBookmark(widget.book, page);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        bookmarked
                            ? t(
                                widget.state,
                                'Bookmark ဖယ်ရှားပြီးပါပြီ',
                                'Bookmark removed',
                              )
                            : t(
                                widget.state,
                                'Bookmark သိမ်းပြီးပါပြီ',
                                'Bookmark saved',
                              ),
                      ),
                    ),
                  );
                },
                icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: page / max),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 34, 26, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t(widget.state, 'စာမျက်နှာ', 'Page')} $page / $max',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      pages[(page - 1).clamp(0, pages.length - 1)],
                      style: const TextStyle(fontSize: 20, height: 1.8),
                    ),
                    const Spacer(),
                    if (widget.preview)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          t(
                            widget.state,
                            'Preview အဆုံးသို့ရောက်ပါပြီ။ Premium ဖြင့် ဆက်ဖတ်နိုင်ပါသည်။',
                            'Preview ends here. Upgrade to Premium to continue.',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: page > 1 ? () => _goTo(page - 1) : null,
                      child: Text(t(widget.state, 'နောက်သို့', 'Previous')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: page < max ? () => _goTo(page + 1) : null,
                      child: Text(t(widget.state, 'ရှေ့သို့', 'Next')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({
    required this.book,
    required this.state,
    required this.file,
    super.key,
  });
  final Book book;
  final AppState state;
  final File file;

  @override
  State<PdfReaderPage> createState() => _PdfReaderState();
}

class _PdfReaderState extends State<PdfReaderPage> {
  int? totalPages;
  int currentPage = 1;
  String? error;

  @override
  void initState() {
    super.initState();
    currentPage = widget.state.readingProgress[widget.book.id] ?? 1;
    widget.state.loadBookmarks(widget.book);
  }

  @override
  Widget build(BuildContext context) {
    final bookmarked =
        widget.state.readingBookmarks[widget.book.id]?.contains(currentPage) ==
        true;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title(widget.state.locale)),
        actions: [
          IconButton(
            onPressed: () async {
              await widget.state.toggleBookmark(widget.book, currentPage);
              if (mounted) setState(() {});
            },
            icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
          ),
        ],
      ),
      body: error != null
          ? Center(child: Text(error!))
          : PDFView(
              filePath: widget.file.path,
              defaultPage: (currentPage - 1).clamp(0, 100000),
              enableSwipe: true,
              swipeHorizontal: false,
              autoSpacing: true,
              pageFling: true,
              onRender: (pages) => setState(() => totalPages = pages),
              onPageChanged: (page, total) {
                final nextPage = (page ?? 0) + 1;
                setState(() {
                  currentPage = nextPage;
                  totalPages = total ?? totalPages;
                });
                widget.state.syncProgress(
                  widget.book,
                  nextPage,
                  total ?? totalPages ?? nextPage,
                );
              },
              onError: (value) => setState(() => error = value.toString()),
              onPageError: (page, value) =>
                  setState(() => error = 'Page $page: $value'),
            ),
    );
  }
}

class PremiumPage extends StatelessWidget {
  const PremiumPage({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    return Frame(
      state: state,
      title: 'Premium',
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Column(
              children: [
                const Icon(Icons.workspace_premium, size: 54),
                const SizedBox(height: 12),
                Text(
                  state.isPremium
                      ? t(state, 'Premium အသုံးပြုနေပါပြီ', 'Premium is active')
                      : t(
                          state,
                          'စာအုပ်တိုင်းကို ဖတ်ရှုပါ',
                          'Read every story',
                        ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t(
                    state,
                    'စာအုပ်အပြည့်အစုံ၊ စိတ်အေးလက်အေးဖတ်ရှုမှုနှင့် စုစည်းထားသောစာကြည့်တိုက်။',
                    'Full access to the collection, in one calm reading experience.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _benefit(
            context,
            Icons.menu_book,
            t(state, 'စာအုပ်အပြည့်အစုံ', 'Full book access'),
          ),
          _benefit(
            context,
            Icons.bookmark,
            t(
              state,
              'Bookmark နှင့် Reading progress',
              'Bookmarks and reading progress',
            ),
          ),
          _benefit(
            context,
            Icons.sync,
            t(state, 'Device များအကြား Sync', 'Sync across devices'),
          ),
          const SizedBox(height: 18),
          if (!state.isPremium && state.premiumProducts.isNotEmpty) ...[
            Text(
              t(state, 'အစီအစဉ်ရွေးချယ်ပါ', 'Choose a plan'),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...state.premiumProducts.map(
              (product) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: state.purchaseLoading
                        ? null
                        : () => state.buyPremium(product),
                    child: Text('${product.title} · ${product.price}'),
                  ),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: state.purchaseLoading ? null : state.restorePremium,
              icon: const Icon(Icons.restore),
              label: Text(t(state, 'ဝယ်ယူမှု ပြန်ယူရန်', 'Restore purchases')),
            ),
            const SizedBox(height: 8),
          ],
          if (!state.isPremium && state.premiumProducts.isEmpty)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(
                      t(
                        state,
                        'Premium စမ်းသပ်ဝယ်ယူမှု',
                        'Premium demo fallback',
                      ),
                    ),
                    content: Text(
                      t(
                        state,
                        'Store product မသတ်မှတ်ရသေးပါက ဒီ demo fallback ဖြင့် entitlement flow ကို စမ်းနိုင်ပါသည်။ Production တွင် native billing နှင့် backend verification ကို အသုံးပြုရပါမည်။',
                        'When store products are not configured, use this demo fallback for local testing. Production must use native billing and backend verification.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(t(state, 'မလုပ်တော့ပါ', 'Cancel')),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final ok = await state.activateDemoPremium();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  state.sessionError ??
                                      t(
                                        state,
                                        'အရင်ဆုံး အကောင့်ဝင်ပါ',
                                        'Sign in first',
                                      ),
                                ),
                              ),
                            );
                          }
                        },
                        child: Text(t(state, 'စမ်းသပ်ဖွင့်ရန်', 'Unlock demo')),
                      ),
                    ],
                  ),
                ),
                child: Text(
                  t(state, 'Premium ဝယ်ယူရန်', 'Subscribe to Premium'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _benefit(BuildContext c, IconData i, String text) => Card(
    child: ListTile(
      leading: Icon(i, color: Theme.of(c).colorScheme.primary),
      title: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.check_circle, color: Colors.green),
    ),
  );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) => Frame(
    state: state,
    title: t(state, 'အကောင့်', 'Profile'),
    child: Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Icon(
                    state.isAdmin ? Icons.admin_panel_settings : Icons.person,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isSignedIn
                            ? (state.isAdmin
                                  ? 'Admin Account'
                                  : 'Reader Account')
                            : t(state, 'ဧည့်သည်', 'Guest'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        state.isPremium
                            ? 'Premium'
                            : t(state, 'Preview access', 'Preview access'),
                      ),
                    ],
                  ),
                ),
                if (!state.isSignedIn)
                  IconButton(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _login(context),
                    ),
                    icon: const Icon(Icons.login),
                  ),
              ],
            ),
          ),
        ),
        if (state.sessionError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              t(
                state,
                'ချိတ်ဆက်မှု မအောင်မြင်ပါ။ ထပ်မံကြိုးစားပါ။',
                'Connection failed. Please try again.',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (state.isSignedIn) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(
                state.userName ?? t(state, 'အသုံးပြုသူ', 'Account holder'),
              ),
              subtitle: Text(
                state.userEmail ??
                    t(state, 'Email မသတ်မှတ်ရသေးပါ', 'Email not available'),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(
                t(state, 'Subscription status', 'Subscription status'),
              ),
              subtitle: Text(
                state.isPremium
                    ? t(state, 'Premium active', 'Premium active')
                    : t(state, 'Preview access only', 'Preview access only'),
              ),
              trailing: IconButton(
                onPressed: state.loadSubscription,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              t(
                state,
                'အကောင့်ဖျက်ရန် တောင်းဆိုမှု',
                'Request account deletion',
              ),
            ),
            subtitle: Text(
              t(
                state,
                'Support team သို့ deletion request ပို့မည်။',
                'Send a deletion request to support.',
              ),
            ),
            onTap: state.accountActionLoading
                ? null
                : () => showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(
                        t(state, 'အကောင့်ဖျက်မည်လား', 'Delete account?'),
                      ),
                      content: Text(
                        t(
                          state,
                          'ဒီလုပ်ဆောင်ချက်က support သို့ request ပို့ပြီးနောက် ဆက်လက်အတည်ပြုမည်။',
                          'This sends a request to support for confirmation before deletion.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(t(state, 'မလုပ်တော့ပါ', 'Cancel')),
                        ),
                        FilledButton(
                          onPressed: () async {
                            final ok = await state.requestAccountDeletion();
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? t(
                                          state,
                                          'Request ပို့ပြီးပါပြီ',
                                          'Request submitted',
                                        )
                                      : (state.sessionError ??
                                            t(
                                              state,
                                              'မအောင်မြင်ပါ',
                                              'Request failed',
                                            )),
                                ),
                              ),
                            );
                          },
                          child: Text(
                            t(state, 'တောင်းဆိုမည်', 'Submit request'),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(t(state, 'အကူအညီနှင့် Support', 'Help and support')),
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(t(state, 'အကူအညီ', 'Help and support')),
              content: Text(
                t(
                  state,
                  'စာအုပ်၊ Premium၊ ငွေပေးချေမှု သို့မဟုတ် account ပြဿနာများအတွက် support team သို့ ဆက်သွယ်ပါ။',
                  'Contact the support team for book, Premium, payment, or account issues.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t(state, 'ပိတ်ရန်', 'Close')),
                ),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.policy_outlined),
          title: Text(t(state, 'Terms နှင့် Privacy', 'Terms and privacy')),
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(t(state, 'Terms နှင့် Privacy', 'Terms and privacy')),
              content: Text(
                t(
                  state,
                  'စာအုပ်ပါအကြောင်းအရာများကို မူပိုင်ခွင့်နှင့် သတ်မှတ်ချက်များအတိုင်း အသုံးပြုရပါမည်။ Privacy policy နှင့် terms ကို production release မတိုင်မီ သင့် domain ဖြင့် အစားထိုးပါ။',
                  'Use book content according to copyright and service terms. Replace this placeholder with your published privacy policy and terms before production release.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t(state, 'ပိတ်ရန်', 'Close')),
                ),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(t(state, 'ဘာသာစကား', 'Language')),
          trailing: Text(
            state.locale.languageCode == 'my' ? 'မြန်မာ' : 'English',
          ),
          onTap: state.toggleLocale,
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(t(state, 'Theme', 'Theme')),
          trailing: Text(state.themeMode.name),
          onTap: state.cycleTheme,
        ),
        if (state.isSignedIn)
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(t(state, 'ထွက်ရန်', 'Sign out')),
            onTap: state.signOut,
          ),
        if (!state.isSignedIn)
          FilledButton.icon(
            onPressed: () =>
                showDialog(context: context, builder: (_) => _login(context)),
            icon: const Icon(Icons.login),
            label: Text(t(state, 'ဝင်ရောက်ရန်', 'Sign in')),
          ),
      ],
    ),
  );
  AlertDialog _login(BuildContext context) => AlertDialog(
    title: Text(t(state, 'အကောင့်ဝင်ရန်', 'Sign in')),
    content: Text(
      t(
        state,
        'Backend session ကို စစ်ဆေးပြီး Reader/Admin role အလိုက် ဝင်ရောက်ပါမည်။ Local backend မချိတ်ထားသေးရင် demo session သုံးနိုင်ပါသည်။',
        'The app will request a backend session and route by Reader/Admin role. A demo session is available when the local backend is not configured.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(t(state, 'အကောင့်ဖန်တီးရန်', 'Create account')),
            content: Text(
              t(
                state,
                'Sign-up ကို သတ်မှတ်ထားသော authentication provider မှ စီမံပါမည်။',
                'Sign-up is handled by the configured authentication provider.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t(state, 'ပိတ်ရန်', 'Close')),
              ),
            ],
          ),
        ),
        child: Text(t(state, 'အကောင့်ဖန်တီးရန်', 'Create account')),
      ),
      TextButton(
        onPressed: state.sessionLoading
            ? null
            : () async {
                final ok = await state.loginDemo(admin: false);
                if (!context.mounted) return;
                if (ok) Navigator.pop(context);
              },
        child: Text(t(state, 'Reader ဝင်ရန်', 'Continue as Reader')),
      ),
      FilledButton(
        onPressed: state.sessionLoading
            ? null
            : () async {
                final ok = await state.loginDemo(admin: true);
                if (!context.mounted) return;
                if (ok) Navigator.pop(context);
              },
        child: Text(t(state, 'Admin ဝင်ရန်', 'Continue as Admin')),
      ),
    ],
  );
}

class AdminPage extends StatelessWidget {
  const AdminPage({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) => Frame(
    state: state,
    title: t(state, 'စီမံခန့်ခွဲမှု', 'Admin'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _metric(
                context,
                Icons.menu_book,
                '${state.books.length}',
                t(state, 'စာအုပ်', 'Books'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metric(
                context,
                Icons.sync,
                '${state.jobs.length}',
                'Jobs',
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          t(state, 'စာအုပ်တင်ရန်', 'Upload a book'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          t(
            state,
            'EPUB သို့မဟုတ် PDF ဖိုင်တင်ပါ။ EPUB ဖိုင်များကို PDF အဖြစ်ပြောင်းပေးမည့် conversion job ဖန်တီးမည်။',
            'Upload an EPUB or PDF. EPUB files create a PDF conversion job.',
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: state.pickFile,
            icon: const Icon(Icons.add_circle_outline),
            label: Text(t(state, 'ဖိုင်ရွေးရန်', 'Choose file')),
          ),
        ),
        if (state.api.hasSession) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.refreshAdminJobs,
                  icon: const Icon(Icons.refresh),
                  label: Text(t(state, 'Jobs ပြန်စစ်ရန်', 'Refresh jobs')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final ok = await state.publishBook(state.books.first);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? t(
                                  state,
                                  'စာအုပ် Publish ပြီးပါပြီ',
                                  'Book published',
                                )
                              : t(
                                  state,
                                  'PDF ပြီးမှ Publish လုပ်ပါ',
                                  'Upload a PDF before publishing',
                                ),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.publish),
                  label: Text(t(state, 'Publish', 'Publish')),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        if (state.jobs.isNotEmpty) ...[
          Text(
            t(state, 'Conversion Jobs', 'Conversion jobs'),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...state.jobs.map(
            (j) => Card(
              child: ListTile(
                leading: Icon(
                  j.status == 'Completed' || j.status == 'Ready'
                      ? Icons.check_circle
                      : j.status == 'Failed'
                      ? Icons.error
                      : Icons.sync,
                  color: j.status == 'Completed' || j.status == 'Ready'
                      ? Colors.green
                      : j.status == 'Failed'
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(j.filename),
                subtitle: Text(j.status),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text(
          t(state, 'Access Control', 'Access control'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user),
            title: const Text('Server-side entitlement verification'),
            subtitle: Text(
              t(
                state,
                'Premium access မပေးမီ backend မှ စစ်ဆေးမည်။',
                'Backend verification is required before full PDF access.',
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget _metric(BuildContext c, IconData i, String value, String label) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(i, color: Theme.of(c).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(label),
            ],
          ),
        ),
      );
}
