/// Models for Jikan API v4 responses
/// Specifically for anime statistics including score distribution

class JikanAnimeStatistics {
  final int? watching;
  final int? completed;
  final int? onHold;
  final int? dropped;
  final int? planToWatch;
  final int? total;
  final List<ScoreStatistics>? scores;

  JikanAnimeStatistics({
    this.watching,
    this.completed,
    this.onHold,
    this.dropped,
    this.planToWatch,
    this.total,
    this.scores,
  });

  factory JikanAnimeStatistics.fromJson(Map<String, dynamic> json) {
    return JikanAnimeStatistics(
      watching: json['watching'] as int?,
      completed: json['completed'] as int?,
      onHold: json['on_hold'] as int?,
      dropped: json['dropped'] as int?,
      planToWatch: json['plan_to_watch'] as int?,
      total: json['total'] as int?,
      scores: json['scores'] != null
          ? (json['scores'] as List<dynamic>)
              .map((dynamic e) => ScoreStatistics.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'watching': watching,
      'completed': completed,
      'on_hold': onHold,
      'dropped': dropped,
      'plan_to_watch': planToWatch,
      'total': total,
      'scores': scores?.map((e) => e.toJson()).toList(),
    };
  }
}

class ScoreStatistics {
  final int? score;
  final int? votes;
  final double? percentage;

  ScoreStatistics({
    this.score,
    this.votes,
    this.percentage,
  });

  factory ScoreStatistics.fromJson(Map<String, dynamic> json) {
    return ScoreStatistics(
      score: json['score'] as int?,
      votes: json['votes'] as int?,
      percentage: (json['percentage'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'votes': votes,
      'percentage': percentage,
    };
  }
}
