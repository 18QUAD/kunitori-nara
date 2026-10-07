import 'dart:math';

enum Difficulty {
  casual('旅人', 25),
  standard('武将', 15),
  expert('天下人', 8);

  const Difficulty(this.label, this.seconds);
  final String label;
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
    final codeGroups = <String, List<Town>>{};
    for (final t in j['towns'] as List) {
      final town = Town.fromJson(t as Map<String, dynamic>);
      sourceTowns[town.id] = town;
      codeGroups.putIfAbsent(town.id.substring(0, 9), () => []).add(town);
    }
    final groups = <String, List<Town>>{};
    for (final entry in codeGroups.entries) {
      final parts = <String, List<Town>>{};
      for (final town in entry.value) {
        // Some census town codes straddle distinct named towns. Keep those apart.
        final part = switch (entry.key) {
          '292015930' ||
          '292060010' ||
          '292060420' ||
          '293430132' => _withoutChome(town.name),
          '294430010' => town.name.startsWith('大字新住') ? '大字新住' : '大字下市',
          _ => '',
        };
        parts.putIfAbsent(part, () => []).add(town);
      }
      for (final part in parts.entries) {
        final names = part.value.map((t) => _withoutChome(t.name)).toList();
        var name = part.key.isNotEmpty ? part.key : names.first;
        if (part.key.isEmpty) {
          for (final other in names.skip(1)) {
            var i = 0;
            while (i < name.length && i < other.length && name[i] == other[i]) {
              i++;
            }
            name = name.substring(0, i);
          }
          if (name.startsWith('大字') && name.length > 2) {
            final sub = name.indexOf('字', 2);
            if (sub >= 0) name = name.substring(0, sub);
          }
        }
        if (name.isEmpty || name == '大字') {
          throw FormatException('町名を特定できません: ${entry.key}');
        }
        groups
            .putIfAbsent('${part.value.first.cityId}:$name', () => [])
            .addAll(part.value);
      }
    }
    for (final entry in groups.entries) {
      final members = entry.value;
      final id = members.first.id;
      for (final member in members) {
        sourceToTown[member.id] = id;
      }
      final merged = Town.fromJson({
        'id': id,
        'name': entry.key
            .substring(entry.key.indexOf(':') + 1)
            .replaceFirst(RegExp(r'^大字'), ''),
        'cityId': members.first.cityId,
        'population': members.fold<int>(0, (s, t) => s + t.population),
        'area': members.fold<double>(0, (s, t) => s + t.area),
        'neighbors': <String>[],
        'polygons': <dynamic>[],
      });
      merged.polygons.addAll(members.expand((t) => t.polygons));
      towns[id] = merged;
      membersByTown[id] = members;
      byCity.putIfAbsent(merged.cityId, () => []).add(merged);
    }
    for (final town in towns.values) {
      for (final source in membersByTown[town.id]!) {
        town.neighbors.addAll(source.neighbors.map((id) => sourceToTown[id]!));
      }
      town.neighbors.remove(town.id);
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
          '${city.value}の攻略対象は$n町。すべての領土を獲得すると地域クイズが始まります。',
          '${city.value}の攻略対象は何町？',
          '$n町',
          ['${n + 1}町', '${max(0, n - 1)}町', '${n + 10}町'],
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
          '${city.value}で収録人口が最も多い町は${largest.first.name}（${number(largest.first.population)}人）です。',
          '${city.value}で収録人口が最も多い町は？',
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
  static String _withoutChome(String name) =>
      name.replaceFirst(RegExp(r'[一二三四五六七八九十百0-9０-９]+丁目$'), '');
  final Map<String, Town> sourceTowns = {};
  final Map<String, String> sourceToTown = {};
  final Map<String, List<Town>> membersByTown = {};
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
  String? home, attackTarget;
  final Set<String> owned = {},
      mastered = {},
      seen = {},
      everOwned = {},
      titles = {};
  final Map<String, int> progress = {};
  final Map<String, int> cityTaps = {};
  bool cityTapsComplete = true;
  int totalTaps = 0, wins = 0, losses = 0;
  Quiz? quiz;
  String message = '';

  int requiredTaps(Town t) => max(1, t.population);
  bool isReachable(String id) =>
      home != null &&
      !owned.contains(id) &&
      (atlas.towns[id]?.neighbors.any(owned.contains) ?? false);
  bool canAttack(String id) =>
      quiz == null &&
      isReachable(id) &&
      (attackTarget == null || attackTarget == id);

  bool selectAttackTarget(String id) {
    if (!isReachable(id) || quiz != null) return false;
    if (attackTarget != null &&
        attackTarget != id &&
        (progress[attackTarget] ?? 0) > 0) {
      return false;
    }
    attackTarget = id;
    return true;
  }

  void _resumePendingTarget() {
    attackTarget = null;
    for (final id in progress.keys) {
      if (isReachable(id)) {
        attackTarget = id;
        break;
      }
    }
  }

  bool cityOwned(String id) =>
      atlas.byCity[id]!.every((t) => owned.contains(t.id));
  int currentCityPopulation(String city) =>
      atlas.byCity[city]!.fold(0, (sum, town) {
        if (owned.contains(town.id)) return sum + town.population;
        return sum + min(progress[town.id] ?? 0, town.population);
      });
  int get population =>
      owned.fold(0, (s, id) => s + atlas.towns[id]!.population) +
      progress.entries
          .where((e) => !owned.contains(e.key))
          .fold(0, (s, e) => s + min(e.value, atlas.towns[e.key]!.population));
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
    attackTarget = id;
    totalTaps++;
    final city = atlas.towns[id]!.cityId;
    cityTaps[city] = (cityTaps[city] ?? 0) + 1;
    progress[id] = (progress[id] ?? 0) + 1;
    if (totalTaps >= 100) titles.add('百の足跡');
    if (totalTaps >= 1000) titles.add('千里の旅人');
    final town = atlas.towns[id]!;
    if (progress[id]! < requiredTaps(town)) return false;
    owned.add(id);
    everOwned.add(id);
    progress.remove(id);
    _resumePendingTarget();
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
    if (attackTarget != null && !isReachable(attackTarget!)) {
      _resumePendingTarget();
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
    'tapRule': 'population-v1',
    'territoryUnit': 'town-v1',
    'difficulty': difficulty.name,
    'home': home,
    'attackTarget': attackTarget,
    'owned': owned.toList(),
    'mastered': mastered.toList(),
    'seen': seen.toList(),
    'everOwned': everOwned.toList(),
    'titles': titles.toList(),
    'progress': progress,
    'totalTaps': totalTaps,
    'cityTaps': cityTaps,
    'cityTapsComplete': cityTapsComplete,
    'wins': wins,
    'losses': losses,
    'quiz': quiz?.toJson(),
  };

  void _migrateTownUnits() {
    final valid = atlas.sourceTowns.keys.toSet();
    if (!valid.containsAll(owned) ||
        !valid.containsAll(everOwned) ||
        !valid.containsAll(progress.keys) ||
        !everOwned.containsAll(owned) ||
        (home != null && !owned.contains(home)) ||
        progress.entries.any((e) => e.value < 0 || owned.contains(e.key))) {
      throw const FormatException('保存データに不整合があります。');
    }
    final oldOwned = {...owned};
    final oldProgress = {...progress};
    home = home == null ? null : atlas.sourceToTown[home];
    final visited = everOwned.map((id) => atlas.sourceToTown[id]!).toSet();
    owned.clear();
    progress.clear();
    everOwned
      ..clear()
      ..addAll(visited);
    for (final entry in atlas.membersByTown.entries) {
      if (entry.key == home ||
          entry.value.every((t) => oldOwned.contains(t.id))) {
        owned.add(entry.key);
        everOwned.add(entry.key);
      } else {
        final count = entry.value.fold<int>(
          0,
          (s, t) =>
              s +
              (oldOwned.contains(t.id)
                  ? t.population
                  : min(oldProgress[t.id] ?? 0, t.population)),
        );
        if (count > 0) {
          progress[entry.key] = min(
            count,
            requiredTaps(atlas.towns[entry.key]!) - 1,
          );
        }
      }
    }
  }

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
    final legacyUnits = j['territoryUnit'] == null;
    if (!legacyUnits && j['territoryUnit'] != 'town-v1') {
      throw const FormatException('対応していない地域単位です。');
    }
    if (legacyUnits) g._migrateTownUnits();
    // Retain acquired territories and adapt legacy partial progress to the new cap.
    if (j['tapRule'] == null) {
      for (final id in g.progress.keys.toList()) {
        final town = atlas.towns[id];
        if (town != null && g.progress[id]! >= 0) {
          g.progress[id] = min(g.progress[id]!, g.requiredTaps(town) - 1);
        }
      }
    } else if (j['tapRule'] != 'population-v1') {
      throw const FormatException('対応していないタップ方式です。');
    }
    g.totalTaps = j['totalTaps'] as int;
    g.cityTapsComplete = j['cityTapsComplete'] as bool? ?? (g.totalTaps == 0);
    if (j['cityTaps'] != null) {
      g.cityTaps.addAll(Map<String, int>.from(j['cityTaps']));
      if (g.cityTaps.entries.any(
        (e) => !atlas.cities.containsKey(e.key) || e.value < 0,
      )) {
        throw const FormatException('市区町村のタップ数が不正です。');
      }
    }
    g.wins = j['wins'] as int;
    g.losses = j['losses'] as int;
    if (j['quiz'] != null) {
      final savedQuiz = Map<String, dynamic>.from(j['quiz']);
      if ((savedQuiz['factId'] as String).endsWith(':largest')) {
        savedQuiz['answer'] = (savedQuiz['answer'] as String).replaceFirst(
          RegExp(r'^大字'),
          '',
        );
        savedQuiz['choices'] =
            List<String>.from(
              savedQuiz['choices'],
            ).map((name) => name.replaceFirst(RegExp(r'^大字'), '')).toList();
      }
      g.quiz = Quiz.fromJson(savedQuiz);
    }
    if (legacyUnits && g.quiz != null) {
      final q = g.quiz!;
      final fs = atlas.facts[q.cityId]?.where((f) => f.id == q.factId).toList();
      if (fs != null &&
          fs.length == 1 &&
          q.choices.length == 4 &&
          q.choices.toSet().length == 4 &&
          q.choices.contains(q.answer)) {
        final f = fs.single;
        g.quiz = Quiz(
          cityId: q.cityId,
          factId: f.id,
          question: f.question,
          answer: f.answer,
          choices: [f.answer, ...f.decoys.take(3)],
          deadline: q.deadline,
        );
      }
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
    g.attackTarget = j['attackTarget'] as String?;
    if (g.attackTarget != null && !validIds.contains(g.attackTarget)) {
      throw const FormatException('攻略先が不正です。');
    }
    if (g.attackTarget == null || !g.isReachable(g.attackTarget!)) {
      g._resumePendingTarget();
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
