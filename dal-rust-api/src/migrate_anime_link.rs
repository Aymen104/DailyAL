use std::collections::HashMap;

use serde_json::Value;

use crate::{cache_service::CacheService, config::Config};
use futures::{stream, StreamExt, TryFutureExt};

pub struct MigrateAnimeLink {
    pub config: Config,
    pub cache_service: CacheService,
}

impl MigrateAnimeLink {
    fn read_links_file(&self) -> Option<String> {
        std::fs::read_to_string("links.json").ok()
    }

    async fn save_links(&self, parsed_db_links: HashMap<String, HashMap<String, String>>) {
        match serde_json::to_string(&parsed_db_links)
            .map(|links| std::fs::write("links.json", links))
        {
            Ok(_) => {
                println!("Links saved successfully");
            }
            Err(_) => {
                println!("Failed to save links");
            }
        }
    }

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

    fn parse_db_links(&self, anime_db: Value) -> HashMap<String, HashMap<String, String>> {
        let sources: HashMap<String, HashMap<String, String>> = anime_db
            .get("data")
            .unwrap()
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|anime| self.extract_sources(anime))
            .collect();
        sources
    }

    fn extract_sources(&self, anime: &Value) -> Option<(String, HashMap<String, String>)> {
        let sources_opt = anime.get("sources").unwrap().as_array();
        if sources_opt.is_none() {
            return None;
        } else {
            let sources = sources_opt.unwrap();
            let collect: HashMap<String, String> = sources
                .iter()
                .filter_map(|source| {
                    let link = source.as_str().unwrap().to_string();
                    self.parse_link(link)
                })
                .collect();
            let mal_id = collect.get("malId");
            if mal_id.is_none() {
                return None;
            }
            Some((mal_id.unwrap().to_string(), collect))
        }
    }

    pub async fn start_migration(&self) -> Result<(), Box<dyn std::error::Error>> {
        let anime_db_optional = self.get_anime_db().await;
        println!("Anime DB captured at time: {}", chrono::Local::now());
        if anime_db_optional.is_none() {
            println!("Failed to fetch anime DB");
            return Ok(());
        }
        let anime_db = anime_db_optional.unwrap();

        let new_db_links = self.parse_db_links(anime_db);
        let old_db_links = self.read_links_file();

        self.save_links(new_db_links.clone()).await;

        let db_links = self.compare_db_links(old_db_links, new_db_links).await;

        stream::iter(db_links)
            .for_each_concurrent(10, |(mal_id, links)| async move {
                let id: String = format!("anime_{}", mal_id);
                self.cache_service.set_link_by_id(&id, links, None).await;
                println!("Saved links for MAL ID: {}", id);
            })
            .await;
        Ok(())
    }

    async fn compare_db_links(
        &self,
        old_db_links: Option<String>,
        new_db_links: HashMap<String, HashMap<String, String>>,
    ) -> HashMap<String, HashMap<String, String>> {
        if old_db_links.is_none() {
            println!("No old links found, saving all new links");
            return new_db_links;
        }
        let old_db_links = old_db_links.unwrap();
        let old_db_links_result: Result<
            HashMap<String, HashMap<String, String>>,
            serde_json::Error,
        > = serde_json::from_str(&old_db_links);
        if old_db_links_result.is_err() {
            println!("Failed to parse old links, saving all new links");
            return new_db_links;
        }
        let old_db_links: HashMap<String, HashMap<String, String>> = old_db_links_result.unwrap();
        let mut diff: HashMap<String, HashMap<String, String>> = HashMap::new();
        for (mal_id, links) in new_db_links {
            if !old_db_links.contains_key(&mal_id) || old_db_links.get(&mal_id) != Some(&links) {
                diff.insert(mal_id, links);
            }
        }
        println!("Found {} new links", diff.len());
        diff
    }
}
