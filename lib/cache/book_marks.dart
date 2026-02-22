// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:dal_commons/commons.dart';
import 'package:dal_commons/dal_commons.dart';
import 'package:flutter/foundation.dart';

class BookMarks {
  Map<String, Node> anime;
  Map<String, Node> manga;
  Map<String, Featured> news;
  Map<String, Featured> featured;
  Map<String, CharacterV4Data> character;
  Map<String, PeopleV4Data> person;
  Map<String, UserProf> malUser;
  Map<String, ForumTopicsData> forumTopics;
  Map<String, InterestStack> interestStacks;
  Map<String, ClubHtml> clubs;
  BookMarks({
    required this.anime,
    required this.manga,
    required this.news,
    required this.featured,
    required this.character,
    required this.person,
    required this.clubs,
    required this.forumTopics,
    required this.interestStacks,
    required this.malUser,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'anime': anime,
      'manga': manga,
      'news': news,
      'featured': featured,
      'character': character,
      'person': person,
      'clubs': clubs,
      'forumTopics': forumTopics,
      'interestStacks': interestStacks,
      'malUser': malUser,
    };
  }

  static BookMarks fromJson(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) {
      return BookMarks(
        anime: {},
        manga: {},
        news: {},
        character: {},
        person: {},
        featured: {},
        clubs: {},
        forumTopics: {},
        interestStacks: {},
        malUser: {},
      );
    }
    return BookMarks(
      anime: fromTJson(map['anime'] as Map<String, dynamic>?, (e) => Node.fromJson(e as Map<String, dynamic>)),
      manga: fromTJson(map['manga'] as Map<String, dynamic>?, (e) => Node.fromJson(e as Map<String, dynamic>)),
      news: fromTJson(map['news'] as Map<String, dynamic>?, (e) => Featured.fromJson(e as Map<String, dynamic>)),
      featured: fromTJson(map['featured'] as Map<String, dynamic>?, (e) => Featured.fromJson(e as Map<String, dynamic>)),
      character:
          fromTJson(map['character'] as Map<String, dynamic>?, (e) => CharacterV4Data.fromJson(e as Map<String, dynamic>)),
      person: fromTJson(map['person'] as Map<String, dynamic>?, (e) => PeopleV4Data.fromJson(e as Map<String, dynamic>)),
      clubs: fromTJson(map['clubs'] as Map<String, dynamic>?, (e) => ClubHtml.fromJson(e as Map<String, dynamic>)),
      forumTopics: fromTJson(
          map['forumTopics'] as Map<String, dynamic>?,
          (dynamic e) => (e as Map<String, dynamic>).containsKey('topic_id')
              ? ForumHtml.fromJson(e)
              : ForumTopicsData.fromJson(e)),
      interestStacks:
          fromTJson(map['interestStacks'] as Map<String, dynamic>?, (e) => InterestStack.fromJson(e as Map<String, dynamic>)),
      malUser: fromTJson(map['malUser'] as Map<String, dynamic>?, (e) => UserProf.fromJson(e as Map<String, dynamic>)),
    );
  }

  static Map<String, T> fromTJson<T>(
      Map<String, dynamic>? map, T Function(dynamic) fromJson) {
    if (map == null) return {};
    return Map.fromEntries(
        map.entries.map((e) => MapEntry(e.key, fromJson(e.value))));
  }

  @override
  String toString() {
    return 'BookMarks(anime: $anime, manga: $manga, news: $news, featured: $featured)';
  }

  @override
  bool operator ==(covariant BookMarks other) {
    if (identical(this, other)) return true;

    return mapEquals(other.anime, anime) &&
        mapEquals(other.manga, manga) &&
        mapEquals(other.news, news) &&
        mapEquals(other.featured, featured);
  }

  @override
  int get hashCode {
    return anime.hashCode ^ manga.hashCode ^ news.hashCode ^ featured.hashCode;
  }
}
