use std::{cmp::min, collections::HashMap, sync::Arc};

use serde_json::Value;
use simsearch::SimSearch;

use crate::{
    config::Config,
    model::{AnimeLink, AnimeQuery},
};
use futures::{lock::Mutex, TryFutureExt};

pub struct AnimeLinkService {
    pub config: Config,
    pub search_engine: Arc<Mutex<SimSearch<String>>>,
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

        let search_engine = self.search_engine.clone();
        let mut search_engine = search_engine.lock().await;
        let link_map = self.link_map.clone();
        let mut link_map = link_map.lock().await;

        for (mal_id, sources) in links.clone() {
            search_engine.delete(&mal_id);
            link_map.insert(mal_id.clone(), sources.clone());
        }

        println!("Inserted {} links into link map", link_map.len());
        println!("Setting up search engine with {} links", links.len());

        for (mal_id, sources) in links {
            let title = sources.title.or(Some("".to_string())).unwrap();
            let search_string = format!("{} {}", title, mal_id);
            search_engine.insert(mal_id.clone(), search_string.as_str());
        }
    }

    pub(crate) async fn search(&self, anime_query: &AnimeQuery) -> Vec<AnimeLink> {
        let query = anime_query.query.clone().unwrap();
        let page = anime_query.page.unwrap_or(1);
        let size = anime_query.size.unwrap_or(20);
        let mut links = vec![];
        let link_map = self.link_map.clone();
        let link_map = link_map.lock().await;
        let search_engine = self.search_engine.clone();
        let search_engine = search_engine.lock().await;
        let results = search_engine.search(&query);
        let start = min(0, (page - 1) * size);
        let end = min(start.saturating_add(size), results.len());
        for result in &results[start..end] {
            if link_map.get(&result.clone()).is_none() {
                continue;
            }
            links.push(link_map.get(&result.clone()).unwrap().clone());
        }
        links
    }

    pub(crate) async fn get_link_by_id(&self, mal_id: String) -> AnimeLink {
        let link_map = self.link_map.clone();
        let link_map = link_map.lock().await;
        let link = link_map.get(&mal_id);
        if link.is_none() {
            return AnimeLink {
                mal_id: Some(mal_id),
                title: None,
                anilist_id: None,
                kitsu_id: None,
                anime_planet: None,
                picture: None,
                year: None,
                synonyms: None,
            };
        }
        link.unwrap().clone()
    }
}
