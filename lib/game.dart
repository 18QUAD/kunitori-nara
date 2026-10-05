import 'dart:math';

enum Difficulty {
  casual('旅人', 0.5, 25),
  standard('武将', 1, 15),
  expert('天下人', 1.8, 8);

  const Difficulty(this.label, this.multiplier, this.seconds);
  final String label;
  final double multiplier;
  final int seconds;
}

class Town {
  Town.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      cityId = j['cityId'] as String,
      population = j['population'] as int,
      area = (j['area'] as num).toDouble(),
      neighbors = Set<String>.from(j['neighbors'] as List),
      polygons =
          (j['polygons'] as List)
              .map(
                (polygon) =>
                    (polygon as List)
                        .map(
                          (ring) =>
                              (ring as List)
                                  .map(
                                    (point) => Point<double>(
                                      (point[0] as num).toDouble(),
                                      (point[1] as num).toDouble(),
                                    ),
                                  )
                                  .toList(),
                        )
                        .toList(),
              )
              .toList();
  final String id, name, cityId;
  final int population;
  final double area;
  final Set<String> neighbors;
  final List<List<List<Point<double>>>> polygons;
}

class LocalFact {
  const LocalFact(
    this.id,
    this.cityId,
    this.category,
    this.text,
    this.question,
    this.answer,
    this.decoys,
    this.source,
  );
  final String id, cityId, category, text, question, answer, source;
  final List<String> decoys;
}

class Atlas {
  Atlas.fromJson(Map<String, dynamic> j) {
    for (final c in j['cities'] as List) {
      cities[c['id'] as String] = c['name'] as String;
    }
    for (final t in j['towns'] as List) {
      final town = Town.fromJson(t as Map<String, dynamic>);
      towns[town.id] = town;
      byCity.putIfAbsent(town.cityId, () => []).add(town);
    }
    for (final city in cities.entries) {
      final ts = byCity[city.key]!;
      final population = ts.fold(0, (s, t) => s + t.population);
      final largest = [...ts]
        ..sort((a, b) => b.population.compareTo(a.population));
      final n = ts.length;
      facts[city.key] = [
        LocalFact(
          '${city.key}:count',
          city.key,
          '地理',
          '${city.value}の攻略対象は$n町丁・字。すべての領土を獲得すると地域クイズが始まります。',
          '${city.value}の攻略対象は何町丁・字？',
          '$n町丁・字',
          ['${n + 1}町丁・字', '${max(0, n - 1)}町丁・字', '${n + 10}町丁・字'],
          censusSource,
        ),
        LocalFact(
          '${city.key}:population',
          city.key,
          '統計',
          '${city.value}の収録地域の人口合計は${number(population)}人。2020年国勢調査の境界データに基づきます。',
          '${city.value}の収録地域の人口合計は？',
          '${number(population)}人',
          [
            '${number(population + 100)}人',
            '${number(max(0, population - 100))}人',
            '${number(population + 1000)}人',
          ],
          censusSource,
        ),
        LocalFact(
          '${city.key}:largest',
          city.key,
          '地域',
          '${city.value}で収録人口が最も多い町丁・字は${largest.first.name}（${number(largest.first.population)}人）です。',
          '${city.value}で収録人口が最も多い町丁・字は？',
          largest.first.name,
          largest
              .skip(1)
              .map((t) => t.name)
              .where((n) => n != largest.first.name)
              .toSet()
              .take(3)
              .toList(),
          censusSource,
        ),
        ..._culture(city.key),
      ];
    }
  }
  static const censusSource = 'https://geoshape.ex.nii.ac.jp/ka/';
  final Map<String, Town> towns = {};
  final Map<String, String> cities = {};
  final Map<String, List<Town>> byCity = {};
  final Map<String, List<LocalFact>> facts = {};

  List<LocalFact> _culture(String city) {
    final result = <LocalFact>[];
    if (city == '29344') {
      result.add(
        LocalFact(
          '$city:heritage',
          city,
          '歴史',
          '斑鳩町の法隆寺には、飛鳥時代の仏教文化を伝える世界最古の木造建造物が残ります。',
          '攻略中に紹介した、斑鳩町にある寺院は？',
          '法隆寺',
          ['東大寺', '薬師寺', '唐招提寺'],
          'https://kunishitei.bunka.go.jp/heritage/detail/911/1',
        ),
      );
    }
    result.add(
      LocalFact(
        '$city:industry',
        city,
        '県の産業',
        '奈良県の中和地域には、靴下やニットなどの繊維産業が集積しています。',
        '紹介した奈良県・中和地域の繊維製品は？',
        '靴下',
        ['タオル', '絹の帯', '帆布'],
        'https://www.pref.nara.lg.jp/n002/1360.html',
      ),
    );
    result.add(
      LocalFact(
        '$city:forest',
        city,
        '県の地理',
        '奈良県では、吉野杉を背景に木材・木製品産業が発達してきました。',
        '紹介した奈良県の木材・木製品産業を支える木は？',
        '吉野杉',
        ['秋田杉', '北山杉', '屋久杉'],
        'https://www.pref.nara.lg.jp/n002/1360.html',
      ),
    );
    return result;
  }
}

String number(num value) => value.round().toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);

class Quiz {
  Quiz({
    required this.cityId,
    required this.factId,
    required this.question,
    required this.answer,
    required this.choices,
    required this.deadline,
  });
  final String cityId, factId, question, answer;
  final List<String> choices;
  final DateTime deadline;
  Map<String, dynamic> toJson() => {
    'cityId': cityId,
    'factId': factId,
    'question': question,
    'answer': answer,
    'choices': choices,
    'deadline': deadline.toIso8601String(),
  };
  factory Quiz.fromJson(Map<String, dynamic> j) => Quiz(
    cityId: j['cityId'],
    factId: j['factId'],
    question: j['question'],
    answer: j['answer'],
    choices: List<String>.from(j['choices']),
    deadline: DateTime.parse(j['deadline']),
  );
}

class Game {
  Game(this.atlas, {Random? random}) : random = random ?? Random();
  final Atlas atlas;
  final Random random;
  Difficulty difficulty = Difficulty.standard;
  String? home;
  final Set<String> owned = {},
      mastered = {},
      seen = {},
      everOwned = {},
      titles = {};
  final Map<String, int> progress = {};
  int totalTaps = 0, wins = 0, losses = 0;
  Quiz? quiz;
  String message = '';

  int requiredTaps(Town t) =>
      max(3, ((6 + sqrt(t.population) * 1.4) * difficulty.multiplier).ceil());
  bool canAttack(String id) =>
      home != null &&
      quiz == null &&
      !owned.contains(id) &&
      atlas.towns[id]!.neighbors.any(owned.contains);
  bool cityOwned(String id) =>
      atlas.byCity[id]!.every((t) => owned.contains(t.id));
  int get population =>
      owned.fold(0, (s, id) => s + atlas.towns[id]!.population);
  double get area => owned.fold(0.0, (s, id) => s + atlas.towns[id]!.area);

  void observe(String city) => seen.addAll(atlas.facts[city]!.map((f) => f.id));
  void setHome(String id) {
    if (home != null || !atlas.towns.containsKey(id)) return;
    home = id;
    owned.add(id);
    everOwned.add(id);
    titles.add('大和への第一歩');
    message = '${atlas.towns[id]!.name}を本拠地にしました。隣接する地域へ進軍しましょう。';
  }

  bool tap(String id, DateTime now) {
    if (!canAttack(id)) return false;
    totalTaps++;
    progress[id] = (progress[id] ?? 0) + 1;
    if (totalTaps >= 100) titles.add('百の足跡');
    if (totalTaps >= 1000) titles.add('千里の旅人');
    final town = atlas.towns[id]!;
    if (progress[id]! < requiredTaps(town)) return false;
    owned.add(id);
    everOwned.add(id);
    progress.remove(id);
    if (everOwned.length >= 10) titles.add('十郷の領主');
    if (everOwned.length >= 100) titles.add('大和の開拓者');
    message = '${town.name}を獲得しました！';
    if (cityOwned(town.cityId) && !mastered.contains(town.cityId)) {
      startQuiz(town.cityId, now);
    }
    return true;
  }

  void startQuiz(String city, DateTime now) {
    if (quiz != null || !cityOwned(city) || mastered.contains(city)) return;
    final pool = atlas.facts[city]!.where((f) => seen.contains(f.id)).toList();
    if (pool.isEmpty) return;
    final fact = pool[random.nextInt(pool.length)];
    final decoys = [...fact.decoys];
    while (decoys.length < 3) {
      decoys.add('該当する地域なし ${decoys.length + 1}');
    }
    if (difficulty == Difficulty.casual) decoys[2] = '鹿がすべて決めている';
    final choices = [fact.answer, ...decoys.take(3)]..shuffle(random);
    quiz = Quiz(
      cityId: city,
      factId: fact.id,
      question: fact.question,
      answer: fact.answer,
      choices: choices,
      deadline: now.add(Duration(seconds: difficulty.seconds)),
    );
    message = '${atlas.cities[city]}の全領土を獲得。地域クイズで制圧を確定！';
  }

  bool? answer(String? choice, DateTime now) {
    final q = quiz;
    if (q == null) return null;
    final correct = now.isBefore(q.deadline) && choice == q.answer;
    quiz = null;
    if (correct) {
      wins++;
      mastered.add(q.cityId);
      titles.add('大和の知恵者');
      message = '正解！ ${atlas.cities[q.cityId]}を制圧しました。';
    } else {
      losses++;
      final candidates =
          atlas.byCity[q.cityId]!
              .where((t) => owned.contains(t.id) && t.id != home)
              .toList()
            ..shuffle(random);
      final count = min(
        candidates.length,
        max(1, (atlas.byCity[q.cityId]!.length * 0.1).ceil()),
      );
      for (final town in candidates.take(count)) {
        owned.remove(town.id);
        progress.remove(town.id);
      }
      mastered.remove(q.cityId);
      message =
          '${choice == null ? '時間切れ' : '不正解'}。正解は「${q.answer}」。$count領土を失いました。本拠地と累計実績は保持されます。';
    }
    return correct;
  }

  bool expire(DateTime now) {
    if (quiz != null && !now.isBefore(quiz!.deadline)) {
      answer(null, now);
      return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'dataset': 'nara-2020-v1',
    'difficulty': difficulty.name,
    'home': home,
    'owned': owned.toList(),
    'mastered': mastered.toList(),
    'seen': seen.toList(),
    'everOwned': everOwned.toList(),
    'titles': titles.toList(),
    'progress': progress,
    'totalTaps': totalTaps,
    'wins': wins,
    'losses': losses,
    'quiz': quiz?.toJson(),
  };

  factory Game.restore(Atlas atlas, Map<String, dynamic> j) {
    if (j['version'] != 1 || j['dataset'] != 'nara-2020-v1') {
      throw const FormatException('対応していない保存データです。');
    }
    final g = Game(atlas);
    g.difficulty = Difficulty.values.firstWhere(
      (d) => d.name == j['difficulty'],
    );
    g.home = j['home'] as String?;
    g.owned.addAll(List<String>.from(j['owned']));
    g.mastered.addAll(List<String>.from(j['mastered']));
    g.seen.addAll(List<String>.from(j['seen']));
    g.everOwned.addAll(List<String>.from(j['everOwned']));
    g.titles.addAll(List<String>.from(j['titles']));
    g.progress.addAll(Map<String, int>.from(j['progress']));
    g.totalTaps = j['totalTaps'] as int;
    g.wins = j['wins'] as int;
    g.losses = j['losses'] as int;
    if (j['quiz'] != null) {
      g.quiz = Quiz.fromJson(Map<String, dynamic>.from(j['quiz']));
    }
    final validIds = atlas.towns.keys.toSet();
    final validFacts =
        atlas.facts.values.expand((f) => f).map((f) => f.id).toSet();
    if (!validIds.containsAll(g.owned) ||
        !validIds.containsAll(g.everOwned) ||
        !g.everOwned.containsAll(g.owned) ||
        !validIds.containsAll(g.progress.keys) ||
        !atlas.cities.keys.toSet().containsAll(g.mastered) ||
        !validFacts.containsAll(g.seen) ||
        g.totalTaps < 0 ||
        g.wins < 0 ||
        g.losses < 0 ||
        (g.home != null && !g.owned.contains(g.home)) ||
        (g.home == null && (g.owned.isNotEmpty || g.quiz != null)) ||
        g.mastered.any((c) => !g.cityOwned(c)) ||
        g.progress.entries.any(
          (e) =>
              e.value < 0 ||
              e.value >= g.requiredTaps(atlas.towns[e.key]!) ||
              g.owned.contains(e.key),
        )) {
      throw const FormatException('保存データに不整合があります。');
    }
    final q = g.quiz;
    if (q != null) {
      final fs = atlas.facts[q.cityId];
      final matching = fs?.where((f) => f.id == q.factId).toList();
      if (matching == null ||
          matching.length != 1 ||
          !g.seen.contains(q.factId) ||
          !g.cityOwned(q.cityId) ||
          g.mastered.contains(q.cityId) ||
          matching.single.answer != q.answer ||
          matching.single.question != q.question ||
          q.choices.length != 4 ||
          q.choices.toSet().length != 4 ||
          !q.choices.contains(q.answer)) {
        throw const FormatException('クイズの保存データに不整合があります。');
      }
    }
    return g;
  }
}
