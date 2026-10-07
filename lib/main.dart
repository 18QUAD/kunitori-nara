import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'game.dart';
import 'save_store.dart';
import 'territory_map.dart';

const ink = Color(0xFF101C2B),
    panel = Color(0xFF192A3A),
    mint = Color(0xFF7AE1BB),
    gold = Color(0xFFEEC47C);
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KunitoriApp());
}

class KunitoriApp extends StatelessWidget {
  const KunitoriApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'くにとり · 奈良',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: 'NotoSansJP',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: const ColorScheme.dark(
        primary: mint,
        secondary: gold,
        surface: panel,
      ),
      useMaterial3: true,
      cardTheme: CardTheme(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const GameScreen(),
  );
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  Atlas? atlas;
  Game? game;
  SaveStore? store;
  String? error, selected;
  String? cityFilter;
  int tab = 0, factIndex = 0, mapFocus = 0, mapCenter = 0;
  Timer? timer, tipsTimer;
  bool corrupt = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    timer?.cancel();
    tipsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (store != null) store!.onChanged = null;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = Atlas.fromJson(
        jsonDecode(await rootBundle.loadString('assets/data/nara.json'))
            as Map<String, dynamic>,
      );
      final saver = SaveStore(await SharedPreferences.getInstance());
      Game g;
      try {
        g = saver.load(data);
      } catch (_) {
        corrupt = true;
        rethrow;
      }
      if (!mounted) return;
      atlas = data;
      game = g;
      store = saver;
      saver.onChanged = () {
        if (mounted) setState(() {});
      };
      selected = g.attackTarget ?? g.home;
      if (selected != null) cityFilter = data.towns[selected]!.cityId;
      g.expire(DateTime.now());
      _rememberVisibleFact();
      setState(() {});
      _startTipsTimer();
      if (g.home != null) _save();
      timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || game!.quiz == null) return;
        final expired = game!.expire(DateTime.now());
        setState(() {});
        if (expired) _save();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error =
                  corrupt
                      ? '保存データを読み込めません。元のデータは保持しています。'
                      : '地図を読み込めませんでした。再試行してください。',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (game == null) return;
    if (state == AppLifecycleState.resumed) {
      game!.expire(DateTime.now());
      setState(() {});
    }
    _save();
  }

  void _save() {
    if (game != null && store != null) unawaited(store!.save(game!));
  }

  Future<void> _restart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('最初からやり直しますか？'),
            content: const Text(
              '本拠地・領土・戦績・称号・地域tipsの履歴をリセットします。元に戻せません。市区町村から新しい本拠地を選び直せます。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('やり直す'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      game = Game(atlas!);
      selected = null;
      cityFilter = null;
      tab = 0;
      factIndex = 0;
      mapFocus = 0;
    });
    _startTipsTimer();
    await store!.save(game!);
  }

  LocalFact? get visibleFact {
    final city = selected == null ? cityFilter : atlas!.towns[selected]!.cityId;
    if (city == null) return null;
    final facts = atlas!.facts[city]!;
    return facts[factIndex % facts.length];
  }

  void _rememberVisibleFact() {
    final f = visibleFact;
    if (f != null) game!.seen.add(f.id);
  }

  void _startTipsTimer() {
    tipsTimer?.cancel();
    tipsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!mounted ||
          game!.quiz != null ||
          visibleFact == null ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        return;
      }
      setState(() {
        factIndex++;
        _rememberVisibleFact();
      });
      _save();
    });
  }

  void _selectCity(String? id) {
    setState(() {
      cityFilter = id;
      selected = null;
      mapFocus = 0;
      factIndex = 0;
      _rememberVisibleFact();
    });
    _startTipsTimer();
    _save();
  }

  bool _select(String id) {
    final g = game!;
    if (g.isReachable(id) && !g.selectAttackTarget(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('攻略先は1か所です。攻略中の町を獲得してから選んでください。')),
      );
      return false;
    }
    setState(() {
      selected = id;
      factIndex = 0;
      tab = 0;
      _rememberVisibleFact();
    });
    _startTipsTimer();
    _save();
    return true;
  }

  void _focusCampaign() {
    final target = game!.attackTarget ?? game!.home;
    if (target == null) return;
    setState(() {
      selected = target;
      tab = 0;
      factIndex = 0;
      _rememberVisibleFact();
      cityFilter = atlas!.towns[target]!.cityId;
      mapFocus++;
      mapCenter++;
    });
    _startTipsTimer();
    _save();
  }

  void _attack() {
    final g = game!;
    final before = g.totalTaps;
    final won = g.tap(selected!, DateTime.now());
    if (g.totalTaps == before) return;
    if (won) HapticFeedback.mediumImpact();
    setState(() {});
    _save();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 48, color: gold),
                const SizedBox(height: 20),
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    setState(() => error = null);
                    _load();
                  },
                  child: const Text('再読み込み'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (game == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 24),
              Text('大和の地図をひらいています…'),
            ],
          ),
        ),
      );
    }
    final g = game!;
    final town = selected == null ? null : atlas!.towns[selected];
    final city = town?.cityId ?? cityFilter;
    final location = [
      '奈良県',
      if (city != null) atlas!.cities[city]!,
      if (town != null) town.name,
    ].join(' ');
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ink,
        titleSpacing: 24,
        toolbarHeight: 88,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: location,
                    child: Text(
                      location,
                      key: const Key('current-location'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (town != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${number(g.owned.contains(town.id) ? town.population : g.progress[town.id] ?? 0)} / ${number(town.population)}',
                    key: const Key('attack-progress'),
                    style: const TextStyle(color: gold, fontSize: 13),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${city == null ? '市区町村未選択' : atlas!.cities[city]!} ${city == null ? "— / —" : "${number(g.currentCityPopulation(city))} / ${number(atlas!.byCity[city]!.fold<int>(0, (sum, t) => sum + t.population))}"}',
                      key: const Key('city-progress'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '奈良県 ${number(g.population)} / ${number(atlas!.towns.values.fold<int>(0, (sum, t) => sum + t.population))}',
                      key: const Key('prefecture-progress'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _about,
            tooltip: '遊び方・データ出典',
            icon: const Icon(Icons.info_outline),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                if (store!.error != null)
                  MaterialBanner(
                    content: Text(store!.error!),
                    actions: [
                      TextButton(onPressed: _save, child: const Text('再試行')),
                    ],
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final topHeight = math.min(
                        constraints.maxHeight * 0.6,
                        math.max(0.0, constraints.maxHeight - 180),
                      );
                      return Column(
                        key: const Key('play-layout'),
                        children: [
                          SizedBox(
                            key: const Key('fixed-region'),
                            height: topHeight,
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 48,
                                  child: Row(
                                    children: [
                                      _viewTab(0, '地図', Icons.map_outlined),
                                      _viewTab(
                                        1,
                                        '戦績',
                                        Icons.emoji_events_outlined,
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: IndexedStack(
                                    index: tab,
                                    children: [_map(), _records()],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: _controls()),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            if (g.quiz != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _quiz(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _viewTab(int index, String label, IconData icon) => Expanded(
    child: Semantics(
      selected: tab == index,
      child: TextButton.icon(
        onPressed:
            game!.quiz != null ? null : () => setState(() => tab = index),
        style: TextButton.styleFrom(
          foregroundColor: tab == index ? mint : Colors.white54,
          backgroundColor: tab == index ? panel : ink,
          shape: const RoundedRectangleBorder(),
          minimumSize: const Size(0, 48),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    ),
  );

  Widget _controls() {
    final tip =
        visibleFact?.text ??
        (cityFilter == null ? '市区町村を選び、次に町から本拠地を選びましょう。' : '町を選んで本拠地を決めましょう。');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          SizedBox(
            key: const Key('tips-region'),
            height: 44,
            width: double.infinity,
            child: Tooltip(
              message: tip,
              child: Text(
                tip,
                key: const Key('tip-text'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _actionPanel()),
        ],
      ),
    );
  }

  Widget _actionPanel() {
    final g = game!;
    final town = selected == null ? null : atlas!.towns[selected];
    if (town == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: Text(
                g.home == null ? '旅のはじまり' : '攻略する町を選んでください',
                style: const TextStyle(color: mint),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _search,
            icon: const Icon(Icons.search),
            label: Text(g.home == null ? '地名から本拠地を探す' : '攻略先を探す'),
          ),
        ],
      );
    }
    if (g.home == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _difficulty(),
          const SizedBox(height: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                g.setHome(town.id);
                setState(() {});
                _save();
              },
              icon: const Icon(Icons.flag),
              label: const Text('ここを本拠地にする'),
            ),
          ),
        ],
      );
    }
    if (g.owned.contains(town.id)) {
      final quizAvailable =
          g.cityOwned(town.cityId) && !g.mastered.contains(town.cityId);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(
            child: Center(
              child: Text('この地域はあなたの領土です', style: TextStyle(color: mint)),
            ),
          ),
          FilledButton.icon(
            onPressed:
                quizAvailable
                    ? () {
                      g.startQuiz(town.cityId, DateTime.now());
                      setState(() {});
                      _save();
                    }
                    : _search,
            icon: Icon(quizAvailable ? Icons.quiz_outlined : Icons.search),
            label: Text(quizAvailable ? '地域クイズに挑戦' : '攻略先を探す'),
          ),
        ],
      );
    }
    final can = g.canAttack(town.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: (g.progress[town.id] ?? 0) / g.requiredTaps(town),
          minHeight: 4,
          color: gold,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FilledButton.icon(
            key: const Key('attack'),
            onPressed: can ? _attack : null,
            style: FilledButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: ink,
            ),
            icon: Icon(can ? Icons.touch_app : Icons.lock_outline),
            label: Text(can ? 'タップで進軍 · 1人' : '隣接する自領が必要です'),
          ),
        ),
      ],
    );
  }

  Widget _map() => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: ColoredBox(
      color: const Color(0xFF122B32),
      child: TerritoryMap(
        atlas: atlas!,
        game: game!,
        selected: selected,
        cityId: cityFilter,
        focusVersion: mapFocus,
        centerVersion: mapCenter,
        onSelected: _select,
        onCitySelected: _selectCity,
        controls: [
          IconButton.filledTonal(
            tooltip: '市町村・町を探す',
            onPressed: _search,
            icon: const Icon(Icons.search),
          ),
          IconButton.filledTonal(
            tooltip: '県全域を表示',
            onPressed: () => _selectCity(null),
            icon: const Icon(Icons.zoom_out_map),
          ),
          IconButton.filledTonal(
            key: const Key('map-home'),
            tooltip: game!.attackTarget == null ? '本拠地へ' : '攻略中の町へ',
            onPressed:
                (game!.attackTarget ?? game!.home) == null
                    ? null
                    : _focusCampaign,
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
    ),
  );
  Widget _difficulty() => DropdownButtonFormField<Difficulty>(
    value: game!.difficulty,
    decoration: const InputDecoration(labelText: '難易度'),
    items:
        Difficulty.values
            .map(
              (d) => DropdownMenuItem(
                value: d,
                child: Text('${d.label} · クイズ${d.seconds}秒'),
              ),
            )
            .toList(),
    onChanged: (d) {
      if (d != null) setState(() => game!.difficulty = d);
    },
  );
  Widget _quiz() {
    final q = game!.quiz!;
    final seconds = math.max(
      0,
      (q.deadline.difference(DateTime.now()).inMilliseconds / 1000).ceil(),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.workspace_premium_outlined,
                size: 44,
                color: gold,
              ),
              const SizedBox(height: 16),
              Text(
                '${atlas!.cities[q.cityId]} · 制圧クイズ',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: gold,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  '残り $seconds 秒',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: seconds <= 5 ? Colors.redAccent : mint,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                q.question,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              ...q.choices.map(
                (answer) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton(
                    onPressed: () {
                      game!.answer(answer, DateTime.now());
                      setState(() {});
                      _save();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      alignment: Alignment.centerLeft,
                    ),
                    child: Text(answer, style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '不正解・時間切れで、この市町村の領土の約10%を失います。本拠地は失いません。アプリを閉じても時間は進みます。',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _records() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        '戦績と足跡',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'この端末に残る、あなただけの大和紀行。',
        style: TextStyle(color: Colors.white60),
      ),
      const SizedBox(height: 20),
      _card(
        Column(
          children: [
            _record('累計タップ数', number(game!.totalTaps)),
            _record('訪れた領土', number(game!.everOwned.length)),
            _record('クイズ正解', number(game!.wins)),
            _record('クイズ失敗', number(game!.losses)),
            _record('難易度', game!.difficulty.label),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        '獲得した称号',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      if (game!.titles.isEmpty) const Text('最初の本拠地を選んで、旅を始めましょう。'),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children:
            game!.titles
                .map(
                  (t) => Chip(
                    avatar: const Icon(
                      Icons.military_tech,
                      color: gold,
                      size: 20,
                    ),
                    label: Text(t),
                    side: const BorderSide(color: Color(0xFF566050)),
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: _restart,
        icon: const Icon(Icons.restart_alt),
        label: const Text('最初からやり直す'),
      ),
      const SizedBox(height: 12),
      const Text(
        'MVPはソロプレイです。全国ランキング・対戦シーズンは未実装です。GDP・石高は未収録のため表示していません。',
        style: TextStyle(color: Colors.white54, height: 1.6),
      ),
    ],
  );
  Widget _record(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white60)),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
    ),
    child: child,
  );
  Future<void> _search() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ink,
      builder:
          (context) =>
              _SearchSheet(atlas: atlas!, game: game!, initialCity: cityFilter),
    );
    if (result != null && mounted) {
      if (!_select(result)) return;
      setState(() {
        cityFilter = atlas!.towns[result]!.cityId;
        mapFocus++;
      });
    }
  }

  void _about() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: panel,
    builder:
        (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder:
              (context, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    '大和国の歩き方',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '1. 市区町村を選び、次に町から本拠地を選択\n2. 金色の隣接地域を選び、タップで攻略\n3. 地域tipsを読み、知識を蓄積（5秒ごとに切替）\n4. 市町村の全領土獲得でクイズに挑戦\n5. 正解で市町村制圧。失敗で一部領土を失う',
                    style: TextStyle(height: 2),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '1タップで1人。人口と同じ回数のタップで町を獲得します。人口0の地域は1タップで獲得します。本拠地の人口は開始時に加算されます。難易度はクイズに適用されます。点で接するだけの地域は隣接扱いにしません。',
                    style: TextStyle(height: 1.7, color: Colors.white70),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '地図と統計',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '奈良県39市町村。2020年国勢調査の3,078町丁字を、丁目・小字をまとめた町・大字単位に統合しています。人口・面積を合算し、統合後の隣接関係を使います。描画用境界のみ簡略化しています。',
                    style: TextStyle(height: 1.7, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  const SelectableText(
                    '国勢調査町丁・字等別境界データセット（CODH作成）\n令和2年国勢調査町丁・字等別境界データ（e-Stat）を加工\ndoi:10.20676/00000450\nhttps://geoshape.ex.nii.ac.jp/ka/\nCC BY 4.0 · https://creativecommons.org/licenses/by/4.0/',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'このMVPの範囲',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '県全域・市町村への移動と町の選択に対応。全国・地方の地図、主要道路ルート、対戦、ランキング、広告は今後の拡張です。保存は端末内のみで、アンインストールやブラウザのデータ削除では失われます。クイズ中にアプリを閉じても締切時刻は変わりません。',
                    style: TextStyle(height: 1.7, color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
        ),
  );
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({
    required this.atlas,
    required this.game,
    this.initialCity,
  });
  final String? initialCity;
  final Atlas atlas;
  final Game game;
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String query = '';
  String? city;
  @override
  void initState() {
    super.initState();
    city = widget.initialCity;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.atlas;
    final towns =
        a.towns.values
            .where(
              (t) =>
                  (city == null || t.cityId == city) &&
                  (t.name.contains(query) ||
                      a.cities[t.cityId]!.contains(query)),
            )
            .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '地名から探す',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: '閉じる',
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: ValueKey(city),
              autofocus: false,
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                hintText: '市区町村・町名で検索',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (city != null)
              TextButton.icon(
                onPressed:
                    () => setState(() {
                      city = null;
                      query = '';
                    }),
                icon: const Icon(Icons.arrow_back),
                label: Text('${a.cities[city]} · 市区町村を選び直す'),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount:
                    city == null
                        ? a.cities.values
                            .where((name) => name.contains(query))
                            .length
                        : towns.length,
                itemBuilder: (context, i) {
                  if (city == null) {
                    final c = a.cities.entries
                        .where((c) => c.value.contains(query))
                        .elementAt(i);
                    return ListTile(
                      title: Text(c.value),
                      subtitle: Text('${a.byCity[c.key]!.length}町'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => setState(() {
                            city = c.key;
                            query = '';
                          }),
                    );
                  }
                  final t = towns[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(t.name),
                    subtitle: Text(
                      '${a.cities[t.cityId]} · ${number(t.population)}人',
                    ),
                    trailing:
                        widget.game.owned.contains(t.id)
                            ? const Icon(Icons.flag, color: mint)
                            : widget.game.canAttack(t.id)
                            ? const Icon(Icons.near_me_outlined, color: gold)
                            : null,
                    onTap: () => Navigator.pop(context, t.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
