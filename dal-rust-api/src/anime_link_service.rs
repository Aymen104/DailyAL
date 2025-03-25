use std::{collections::HashMap, sync::Arc};

use serde_json::Value;
use simsearch::SimSearch;

use crate::{config::Config, model::AnimeLink};
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

    fn parse_link(&self, link: String) -> Option<(String, String)> {
        let parts: Vec<&str> = link.split("/").collect();
        let id = parts.last().unwrap_or(&"").to_string();
        if id.is_empty() {
            return None;
        }
        if link.contains("myanimelist") {
            return Some(("malId".to_string(), id));
        } else if link.contains("anilist") {
            return Some(("anilistId".to_string(), id));
        } else if link.contains("kitsu") {
            return Some(("kitsuId".to_string(), id));
        } else if link.contains("anime-planet") {
            return Some(("animePlanetId".to_string(), id));
        }
        return None;
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

    fn extract_sources(&self, anime: &Value) -> Option<(String, HashMap<String, String>)> {
        let sources_opt = anime.get("sources").unwrap().as_array();
        if sources_opt.is_none() {
            return None;
        } else {
            let sources = sources_opt.unwrap();
            let mut collect: HashMap<String, String> = sources
                .iter()
                .filter_map(|source| {
                    let link = source.as_str().unwrap().to_string();
                    self.parse_link(link)
                })
                .collect();
            let mal_id = collect.get("malId").cloned();
            if mal_id.is_none() {
                return None;
            }
            let title = anime.get("title").unwrap().as_str().unwrap().to_string();
            collect.insert("title".to_string(), title);
            Some((mal_id.unwrap().to_string(), collect))
        }
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
            link_map.insert(mal_id.clone(), sources.clone());
        }

        println!("Inserted {} links into link map", link_map.len());
        println!("Setting up search engine with {} links", links.len());

        for (mal_id, sources) in links {
            let title = sources.title.or(Some("".to_string())).unwrap();
            let search_string = format!("{} {}", title, mal_id);
            search_engine.insert(mal_id, search_string.as_str());
        }
    }

    pub(crate) async fn search(&self, query: String) -> Vec<AnimeLink> {
        let search_engine = self.search_engine.clone();
        let search_engine = search_engine.lock().await;
        let results = search_engine.search(&query);
        let mut links = vec![];
        let link_map = self.link_map.clone();
        let link_map = link_map.lock().await;
        for result in results {
            if link_map.get(&result).is_none() {
                continue;
            }
            links.push(link_map.get(&result).unwrap().clone());
        }
        links[0..10].to_vec()
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
            };
        }
        link.unwrap().clone()
    }
}
