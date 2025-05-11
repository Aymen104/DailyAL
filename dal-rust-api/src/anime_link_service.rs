use std::{cmp::{min, Ordering}, collections::HashMap, sync::Arc};

use serde_json::Value;

use crate::{
    config::Config,
    model::{AnimeLink, AnimeQuery},
};
use futures::{lock::Mutex, TryFutureExt};

pub struct AnimeLinkService {
    pub config: Config,
    pub link_map: Arc<Mutex<HashMap<String, AnimeLink>>>,
}

impl AnimeLinkService {
    async fn get_anime_db(&self) -> Option<Value> {
        let anime_db_url = self.config.secrets.anime_db_url.clone();
        println!("Fetching anime DB from: {}", anime_db_url);

        reqwest::get(&anime_db_url)
            .map_ok(|res| res.text())
            .try_flatten()
            .map_ok(|body| serde_json::from_str(&body).unwrap())
            .await
            .ok()
    }

    fn extract_sources(&self, anime: &Value) -> Option<(String, AnimeLink)> {
        let sources_opt = anime.get("sources").map(|f| f.as_array()).flatten();
        if sources_opt.is_none() {
            return None;
        } else {
            let anime_link: AnimeLink = anime.clone().into();
            let mal_id = anime_link.mal_id.clone();
            if mal_id.is_none() {
                return None;
            }
            let mal_id = mal_id.unwrap();
            return Some((mal_id, anime_link));
        }
    }

    fn parse_db_links(&self, anime_db: Value) -> HashMap<String, AnimeLink> {
        let sources: HashMap<String, AnimeLink> = anime_db
            .get("data")
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|anime| self.extract_sources(anime))
            .into_iter()
            .map(|(mal_id, map)| (mal_id, map.into()))
            .collect();
        sources
    }

    pub(crate) async fn setup_links(&self) {
        let anime_db_optional = self.get_anime_db().await;
        println!("Anime DB captured at time: {}", chrono::Local::now());
        if anime_db_optional.is_none() {
            println!("Failed to fetch anime DB");
            return;
        }
        let anime_db = anime_db_optional.unwrap();
        let links = self.parse_db_links(anime_db);

        let link_map = self.link_map.clone();
        let mut link_map = link_map.lock().await;

        for (mal_id, sources) in links.clone() {
            link_map.insert(mal_id.clone(), sources.clone());
        }

        println!("Inserted {} links into link map", link_map.len());
    }

    pub(crate) async fn search(&self, anime_query: &AnimeQuery) -> Vec<AnimeLink> {
        let query = anime_query.query.clone().unwrap();
        let page = anime_query.page.unwrap_or(1);
        let size = anime_query.size.unwrap_or(20);
        let mut links = vec![];
        let link_map = self.link_map.clone();
        let link_map = link_map.lock().await;
        let results = search_in_links_map(query, &link_map);
        let start = min(0, (page - 1) * size);
        let end = min(start.saturating_add(size), results.len());
        for result in &results[start..end] {
            links.push(result.clone());
        }
        links
    }

    pub(crate) async fn get_link_by_id(&self, mal_id: &String) -> AnimeLink {
        let link_map = self.link_map.clone();
        let link_map = link_map.lock().await;
        let link = link_map.get(mal_id);
        if link.is_none() {
            return AnimeLink {
                mal_id: Some(mal_id.to_string()),
                title: None,
                anilist_id: None,
                kitsu_id: None,
                anime_planet: None,
                picture: None,
                year: None,
                synonyms: None,
                mean: 0.0,
            };
        }
        link.unwrap().clone()
    }

    pub(crate) async fn get_all_anime(&self) -> Vec<AnimeLink> {
        let link_map = self.link_map.clone();
        let link_map = link_map.lock().await;
        let mut links: Vec<AnimeLink> = link_map.values().cloned().collect();
        links.sort_by(|a, b| self.compare_anime_links_by_mean_score(a, b));
        links
    }

    fn compare_anime_links_by_mean_score(&self, a: &AnimeLink, b: &AnimeLink) -> Ordering {
        let a_mean = a.mean;
        let b_mean = b.mean;
        if a_mean > b_mean {
            Ordering::Less
        } else if a_mean < b_mean {
            Ordering::Greater
        } else {
            Ordering::Equal
        }
    }
}

fn search_in_links_map(
    query: String,
    link_map: &futures::lock::MutexGuard<'_, HashMap<String, AnimeLink>>,
) -> Vec<AnimeLink> {
    link_map
        .iter()
        .filter(|(_, anime)| {
            if anime.title.is_none() {
                return false;
            }
            let title = anime.title.as_ref().unwrap();
            title.to_lowercase().contains(&query.to_lowercase())
                || anime
                    .synonyms
                    .as_ref()
                    .unwrap_or(&vec![])
                    .iter()
                    .any(|synonym| synonym.to_lowercase().contains(&query.to_lowercase()))
        })
        .map(|(_, anime)| anime.clone())
        .collect::<Vec<AnimeLink>>()
}
