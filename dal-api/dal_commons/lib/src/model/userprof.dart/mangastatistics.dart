/// Statistics block returned by the MAL API under `manga_statistics`.
///
/// The app has been requesting `manga_statistics` since it was added to the
/// `fields` list, but `UserProf` had no matching property so the whole payload
/// was parsed and thrown away. Mirrors [UserAnimeStatistics] for the manga side.
class UserMangaStatistics {
  final double? numItemsReading;
  final double? numItemsCompleted;
  final double? numItemsOnHold;
  final double? numItemsDropped;
  final double? numItemsPlanToRead;
  final double? numItems;
  final double? numDaysReading;
  final double? numDaysCompleted;
  final double? numDaysOnHold;
  final double? numDaysDropped;
  final double? numDays;
  final double? numChapters;
  final double? numVolumes;
  final double? numTimesReread;
  final double? meanScore;

  UserMangaStatistics(
      {this.numItemsReading,
      this.numItemsCompleted,
      this.numItemsOnHold,
      this.numItemsDropped,
      this.numItemsPlanToRead,
      this.numItems,
      this.numDaysReading,
      this.numDaysCompleted,
      this.numDaysOnHold,
      this.numDaysDropped,
      this.numDays,
      this.numChapters,
      this.numVolumes,
      this.numTimesReread,
      this.meanScore});

  factory UserMangaStatistics.fromJson(Map<String, dynamic>? json) {
    return json != null
        ? UserMangaStatistics(
            meanScore: double.tryParse(json["mean_score"].toString()),
            numDays: double.tryParse(json["num_days"].toString()),
            numDaysCompleted:
                double.tryParse(json["num_days_completed"].toString()),
            numDaysDropped:
                double.tryParse(json["num_days_dropped"].toString()),
            numDaysOnHold: double.tryParse(json["num_days_on_hold"].toString()),
            numDaysReading:
                double.tryParse(json["num_days_reading"].toString()),
            numChapters: double.tryParse(json["num_chapters"].toString()),
            numItems: double.tryParse(json["num_items"].toString()),
            numItemsCompleted:
                double.tryParse(json["num_items_completed"].toString()),
            numItemsDropped:
                double.tryParse(json["num_items_dropped"].toString()),
            numItemsOnHold:
                double.tryParse(json["num_items_on_hold"].toString()),
            numItemsPlanToRead:
                double.tryParse(json["num_items_plan_to_read"].toString()),
            numItemsReading:
                double.tryParse(json["num_items_reading"].toString()),
            numTimesReread:
                double.tryParse(json["num_times_reread"].toString()),
            numVolumes: double.tryParse(json["num_volumes"].toString()))
        : UserMangaStatistics();
  }

  Map<String, dynamic> toJson() {
    return {
      "num_items_reading": numItemsReading,
      "num_items_completed": numItemsCompleted,
      "num_items_on_hold": numItemsOnHold,
      "num_items_dropped": numItemsDropped,
      "num_items_plan_to_read": numItemsPlanToRead,
      "num_items": numItems,
      "num_days_reading": numDaysReading,
      "num_days_completed": numDaysCompleted,
      "num_days_on_hold": numDaysOnHold,
      "num_days_dropped": numDaysDropped,
      "num_days": numDays,
      "num_chapters": numChapters,
      "num_volumes": numVolumes,
      "num_times_reread": numTimesReread,
      "mean_score": meanScore
    };
  }
}
