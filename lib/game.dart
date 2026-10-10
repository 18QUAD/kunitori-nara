import 'dart:math';
import 'regional_tips.dart';
import 'municipal_offices.dart';
import 'municipal_office.dart';

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
    this.source, {
    this.quizEligible = true,
  });
  final String id, cityId, category, text, question, answer, source;
  final List<String> decoys;
  final bool quizEligible;
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
    for (final office in municipalOffices) {
      final townId = sourceToTown[office.sourceTownId];
      if (townId == null || towns[townId]!.cityId != office.cityId) {
        throw FormatException('役所所在地が地図と一致しません: ${office.name}');
      }
      offices[office.cityId] = office;
      officeTownIds[office.cityId] = townId;
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
          '${city.value}の攻略対象は$n町。すべての領土を獲得したら、役所・役場のある町をタップして制圧クイズに挑戦できます。',
          '${city.value}の攻略対象は何町？',
          '$n町',
          ['${max(1, n ~/ 2)}町', '${n * 2}町', '${n * 3}町'],
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
            '${number(population / 2)}人',
            '${number(population * 2)}人',
            '${number(population * 3)}人',
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
          [...largest.skip(1)].reversed
              .map((t) => t.name)
              .where(
                (n) =>
                    n != largest.first.name &&
                    !n.startsWith(
                      largest.first.name.substring(
                        0,
                        min(2, largest.first.name.length),
                      ),
                    ),
              )
              .toSet()
              .take(3)
              .toList(),
          censusSource,
        ),
        ..._culture(city.key),
        ...regionalTips
            .where((tip) => tip['cityId'] == city.key)
            .map(
              (tip) => LocalFact(
                tip['id']!,
                city.key,
                tip['category']!,
                tip['text']!,
                '',
                '',
                const [],
                tip['source']!,
                quizEligible: false,
              ),
            ),
      ];
    }
  }
  static const censusSource = 'https://geoshape.ex.nii.ac.jp/ka/';
  static String _withoutChome(String name) =>
      name.replaceFirst(RegExp(r'[一二三四五六七八九十百0-9０-９]+丁目$'), '');
  final Map<String, MunicipalOffice> offices = {};
  final Map<String, String> officeTownIds = {};
  MunicipalOffice? officeForTown(String id) {
    final city = towns[id]?.cityId;
    return officeTownIds[city] == id ? offices[city] : null;
  }

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
          '斑鳩町の法隆寺には、飛鳥の仏教文化を伝える世界最古の木造建造物が残ります。',
          '攻略中に紹介した、斑鳩町にある寺院は？',
          '法隆寺',
          ['清水寺', '金閣寺', '浅草寺'],
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
        ['陶磁器', '漆器', 'ガラス食器'],
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
        ['松', '桜', '竹'],
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

class QuizQuestion {
  const QuizQuestion({
    required this.factId,
    required this.question,
    required this.answer,
    required this.choices,
  });
  final String factId, question, answer;
  final List<String> choices;
  Map<String, dynamic> toJson() => {
    'factId': factId,
    'question': question,
    'answer': answer,
    'choices': choices,
  };
  factory QuizQuestion.fromJson(Map<String, dynamic> j) => QuizQuestion(
    factId: j['factId'],
    question: j['question'],
    answer: j['answer'],
    choices: List<String>.from(j['choices']),
  );
}

class Quiz extends QuizQuestion {
  Quiz({
    required this.cityId,
    required super.factId,
    required super.question,
    required super.answer,
    required super.choices,
    required this.deadline,
    this.correctCount = 0,
    this.remaining = const [],
  });
  final String cityId;
  final DateTime deadline;
  final int correctCount;
  final List<QuizQuestion> remaining;
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'cityId': cityId,
    'deadline': deadline.toIso8601String(),
    'correctCount': correctCount,
    'remaining': remaining.map((q) => q.toJson()).toList(),
  };
  factory Quiz.fromJson(Map<String, dynamic> j) => Quiz(
    cityId: j['cityId'],
    factId: j['factId'],
    question: j['question'],
    answer: j['answer'],
    choices: List<String>.from(j['choices']),
    deadline: DateTime.parse(j['deadline']),
    correctCount: j['correctCount'] ?? 0,
    remaining: [
      for (final q in j['remaining'] ?? [])
        QuizQuestion.fromJson(Map<String, dynamic>.from(q)),
    ],
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
      ((atlas.towns[id]?.neighbors.any(owned.contains) ?? false) ||
          (everOwned.contains(id) &&
              atlas.officeForTown(id) != null &&
              atlas.byCity[atlas.towns[id]!.cityId]!.every(
                (t) => t.id == id || owned.contains(t.id),
              )));
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

  List<LocalFact> tipsFor({String? selectedTown, String? selectedCity}) {
    final target = attackTarget ?? selectedTown;
    final city =
        target == null
            ? selectedCity ?? (home == null ? null : atlas.towns[home]?.cityId)
            : atlas.towns[target]?.cityId;
    if (city == null) return const [];
    final local = atlas.facts[city]!;
    return [
      ...local.where((f) => !f.quizEligible),
      ...local.where((f) => f.id == '$city:heritage'),
      ...local.where((f) => f.category.startsWith('県の')),
    ];
  }

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
      message =
          '${atlas.cities[town.cityId]}の全領土を獲得。${atlas.offices[town.cityId]!.name}のある町をタップして制圧クイズに挑戦できます。';
    }
    return true;
  }

  bool canStartQuizAt(String townId) {
    final town = atlas.towns[townId];
    return town != null &&
        quiz == null &&
        atlas.officeTownIds[town.cityId] == townId &&
        cityOwned(town.cityId) &&
        !mastered.contains(town.cityId);
  }

  QuizQuestion _makeQuestion(LocalFact fact) {
    final decoys =
        fact.decoys.where((a) => a != fact.answer).toSet().toList()
          ..shuffle(random);
    // Very small municipalities may not have two distinct alternative town names.
    for (final fallback in ['奈良公園', '関西国際空港', '富士山']) {
      if (decoys.length >= 2) break;
      if (fallback != fact.answer && !decoys.contains(fallback)) {
        decoys.add(fallback);
      }
    }
    final jokes = switch (fact.id.split(':').last) {
      'count' => ['鹿の気分で毎朝変わる', '鹿せんべいの枚数と同じ', '鹿が数え終わるまで未定'],
      'population' => ['鹿も数えるので測定不能', '鹿せんべい1枚につき1人', '全員忍者なので数えられない'],
      'largest' => ['鹿せんべい銀河団', '空飛ぶ鹿の秘密基地', '地下のせんべい王国'],
      'heritage' => ['鹿せんべい神殿', '空飛ぶ大仏の別荘', '鹿の宇宙ステーション'],
      'industry' => ['鹿専用の宇宙服', '鹿専用のロケット', '透明になる鹿せんべい'],
      _ => ['せんべいが実る木', '空飛ぶ鹿のなる木', '大仏の盆栽'],
    };
    return QuizQuestion(
      factId: fact.id,
      question: fact.question,
      answer: fact.answer,
      choices: [
        fact.answer,
        ...decoys.take(2),
        jokes[random.nextInt(jokes.length)],
      ]..shuffle(random),
    );
  }

  bool canPracticeAt(String townId) {
    final town = atlas.towns[townId];
    return town != null &&
        atlas.officeTownIds[town.cityId] == townId &&
        owned.contains(townId);
  }

  List<QuizQuestion> practiceQuestionsAt(String townId) {
    if (!canPracticeAt(townId)) return [];
    return _quizQuestions(atlas.towns[townId]!.cityId);
  }

  List<QuizQuestion> _quizQuestions(String city) {
    final pool =
        atlas.facts[city]!.where((f) => f.quizEligible).toList()
          ..shuffle(random);
    if (pool.length < 5) throw StateError('制圧クイズには異なる5問が必要です');
    return pool.take(5).map(_makeQuestion).toList();
  }

  // Only the office territory can open a new challenge; taking the last town never starts it.
  void startQuizAt(String townId, DateTime now) {
    if (!canStartQuizAt(townId)) return;
    final city = atlas.towns[townId]!.cityId;
    final questions = _quizQuestions(city);
    final first = questions.first;
    quiz = Quiz(
      cityId: city,
      factId: first.factId,
      question: first.question,
      answer: first.answer,
      choices: first.choices,
      deadline: now.add(Duration(seconds: difficulty.seconds)),
      remaining: questions.skip(1).toList(),
    );
    message = '${atlas.cities[city]}の制圧クイズ。4択5問すべてに正解するとクリア！';
  }

  bool? answer(
    String? choice,
    DateTime now, {
    Duration nextQuestionDelay = Duration.zero,
  }) {
    final q = quiz;
    if (q == null) return null;
    final correct = now.isBefore(q.deadline) && choice == q.answer;
    if (correct && q.remaining.isNotEmpty) {
      final next = q.remaining.first;
      quiz = Quiz(
        cityId: q.cityId,
        factId: next.factId,
        question: next.question,
        answer: next.answer,
        choices: next.choices,
        correctCount: q.correctCount + 1,
        remaining: q.remaining.skip(1).toList(),
        deadline: now.add(
          Duration(seconds: difficulty.seconds) + nextQuestionDelay,
        ),
      );
      return true;
    }
    quiz = null;
    if (correct) {
      wins++;
      mastered.add(q.cityId);
      titles.add('大和の知恵者');
      message = 'すごい、5問とも正解だよ！ ${atlas.cities[q.cityId]}を制圧できたね。おめでとう！';
    } else {
      losses++;
      final officeTown = atlas.officeTownIds[q.cityId]!;
      owned.remove(officeTown);
      progress.remove(officeTown);
      mastered.remove(q.cityId);
      message =
          '${choice == null ? '時間切れになっちゃったね' : '今回は不正解だったね'}。正解は「${q.answer}」だよ。${atlas.offices[q.cityId]!.name}所在地の${atlas.towns[officeTown]!.name}の支配を失ったけれど、再攻略すればまた挑戦できるよ！';
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
    'quizRule': 'office-five-v1',
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
    final legacyQuiz = j['quizRule'] == null;
    if (!legacyQuiz && j['quizRule'] != 'office-five-v1') {
      throw const FormatException('対応していないクイズ方式です。');
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
        final updated = g._makeQuestion(f);
        g.quiz = Quiz(
          cityId: q.cityId,
          factId: f.id,
          question: f.question,
          answer: f.answer,
          choices: updated.choices,
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
        (g.home != null &&
            (!validIds.contains(g.home) ||
                !g.everOwned.contains(g.home) ||
                (!g.owned.contains(g.home) &&
                    (legacyQuiz || atlas.officeForTown(g.home!) == null)))) ||
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
          (legacyQuiz && !g.seen.contains(q.factId)) ||
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
    if (g.quiz != null) {
      final q = g.quiz!;
      if (legacyQuiz) {
        // Keep the current question and its original deadline; append four distinct questions.
        final pool =
            atlas.facts[q.cityId]!
                .where((f) => f.quizEligible && f.id != q.factId)
                .toList();
        g.quiz = Quiz(
          cityId: q.cityId,
          factId: q.factId,
          question: q.question,
          answer: q.answer,
          choices: q.choices,
          deadline: q.deadline,
          remaining: pool.take(4).map(g._makeQuestion).toList(),
        );
      }
      final current = g.quiz!;
      final questions = <QuizQuestion>[current, ...current.remaining];
      if (current.correctCount < 0 ||
          current.correctCount > 4 ||
          current.correctCount + questions.length != 5 ||
          questions.map((q) => q.factId).toSet().length != questions.length ||
          questions.any((question) {
            final matching =
                atlas.facts[current.cityId]!
                    .where((f) => f.id == question.factId && f.quizEligible)
                    .toList();
            return matching.length != 1 ||
                matching.single.question != question.question ||
                matching.single.answer != question.answer ||
                question.choices.length != 4 ||
                question.choices.toSet().length != 4 ||
                !question.choices.contains(question.answer);
          })) {
        throw const FormatException('5問クイズの保存データに不整合があります。');
      }
    }
    return g;
  }
}
