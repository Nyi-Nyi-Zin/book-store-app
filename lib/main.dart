import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const BookApp());

class Book {
  const Book({
    required this.id,
    required this.titleMy,
    required this.titleEn,
    required this.author,
    required this.description,
    required this.color,
  });
  final String id, titleMy, titleEn, author, description;
  final Color color;
  String title(Locale locale) =>
      locale.languageCode == 'my' ? titleMy : titleEn;
}

class ConversionJob {
  ConversionJob(this.filename);
  final String filename;
  String status = 'Queued';
}

class AppState extends ChangeNotifier {
  Locale locale = const Locale('my');
  ThemeMode themeMode = ThemeMode.system;
  bool isPremium = false, isAdmin = false, isSignedIn = false;
  bool _localeChanged = false, _themeChanged = false;
  int tabIndex = 0;
  final jobs = <ConversionJob>[];
  final readingProgress = <String, int>{};
  final books = const [
    Book(
      id: 'midnight-river',
      titleMy: 'ညသန်းခေါင်က မြစ်',
      titleEn: 'The Midnight River',
      author: 'Aye Thiri',
      description: 'A quiet novel about memory, distance, and the choices that bring people home.',
      color: Color(0xff6d5dfc),
    ),
    Book(
      id: 'rain-letter',
      titleMy: 'မိုးရေစက်စာ',
      titleEn: 'Letters in the Rain',
      author: 'Min Thu',
      description: 'Two unfinished letters become a journey through Yangon, Mandalay, and old promises.',
      color: Color(0xffd46b4c),
    ),
    Book(
      id: 'last-lantern',
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
    tabIndex = 0;
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

  Future<void> pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf'],
    );
    if (files.isEmpty) return;
    final file = files.first;
    final job = ConversionJob(file.name);
    jobs.insert(0, job);
    notifyListeners();
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
                    onPressed: () {
                      if (state.isPremium) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReaderPage(
                              book: book,
                              state: state,
                              preview: false,
                            ),
                          ),
                        );
                      } else {
                        state.setTab(2);
                        Navigator.pop(context);
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
  }

  void _goTo(int nextPage) {
    setState(() => page = nextPage);
    widget.state.setProgress(widget.book.id, page);
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
          IconButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  t(widget.state, 'Bookmark သိမ်းပြီးပါပြီ', 'Bookmark saved'),
                ),
              ),
            ),
            icon: const Icon(Icons.bookmark_border),
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
          if (!state.isPremium)
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
                        'Premium test purchase',
                      ),
                    ),
                    content: Text(
                      t(
                        state,
                        'Production တွင် App Store/Google Play billing နှင့် backend verification ကို ချိတ်ဆက်ပါမည်။ ယခု demo တွင် entitlement flow ကို စမ်းသပ်နိုင်ပါသည်။',
                        'Production will connect App Store/Google Play billing with server verification. This demo tests the entitlement flow.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(t(state, 'မလုပ်တော့ပါ', 'Cancel')),
                      ),
                      FilledButton(
                        onPressed: () {
                          state.unlockDemo();
                          Navigator.pop(context);
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
        'Production backend တွင် OAuth login ချိတ်ဆက်မည်။ Demo တွင် role flow ကို စမ်းနိုင်ပါသည်။',
        'OAuth login will connect to the production backend. Use demo roles to test the flows.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          state.signIn();
          Navigator.pop(context);
        },
        child: Text(t(state, 'Reader', 'Reader demo')),
      ),
      FilledButton(
        onPressed: () {
          state.signIn(admin: true);
          Navigator.pop(context);
        },
        child: Text(t(state, 'Admin', 'Admin demo')),
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
                      : Icons.sync,
                  color: j.status == 'Completed' || j.status == 'Ready'
                      ? Colors.green
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
