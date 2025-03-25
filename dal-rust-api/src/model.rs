use std::collections::HashMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Anime {
    pub id: i64,
    pub title: String,
    pub main_picture: Option<MainPicture>,
    pub mean: Option<f64>,
    pub media_type: Option<String>,
    pub status: Option<String>,
    pub start_season: Option<Season>,
    pub related_anime: Option<Vec<RelatedAnime>>,
    pub alternative_titles: Option<AlternateTitles>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlternateTitles {
    pub en: Option<String>,
    pub ja: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MainPicture {
    pub medium: String,
    pub large: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelatedAnime {
    pub node: Node,
    pub relation_type: RelationType,
    pub relation_type_formatted: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Node {
    pub id: i64,
    pub title: String,
    pub main_picture: MainPicture,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Season {
    pub year: i64,
    pub season: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Edge {
    pub source: i64,
    pub target: i64,
    pub relation_type: RelationType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RelationType {
    #[serde(rename = "sequel")]
    Sequel,
    #[serde(rename = "prequel")]
    Prequel,
    #[serde(rename = "alternative_setting")]
    AlternativeSetting,
    #[serde(rename = "alternative_version")]
    AlternativeVersion,
    #[serde(rename = "side_story")]
    SideStory,
    #[serde(rename = "parent_story")]
    ParentStory,
    #[serde(rename = "summary")]
    Summary,
    #[serde(rename = "full_story")]
    FullStory,
    #[serde(rename = "spin_off")]
    SpinOff,
    #[serde(rename = "character")]
    Character,
    #[serde(rename = "other")]
    Other,
}

#[derive(Debug, Clone)]
pub struct AnimeQuery {
    pub mal_id: Option<String>,
    pub query: Option<String>,
}
impl AnimeQuery {
    pub fn from_headers(headers: axum::http::HeaderMap) -> AnimeQuery {
        AnimeQuery {
            mal_id: headers.get("mal_id").map(|v| v.to_str().unwrap().to_string()),
            query: headers.get("query").map(|v| v.to_str().unwrap().to_string()),
        }
    }
}

pub struct File {
    pub content: Vec<u8>,
    pub content_type: String,
    pub file_name: String,
}

#[derive(Clone, Deserialize, Serialize, Debug)]
pub struct ReviewResponse {
    pros: Vec<ReviewItem>,
    cons: Vec<ReviewItem>,
    verdict: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewResponseData {
    pub data: ReviewResponse,
}

#[derive(Clone, Deserialize, Serialize, Debug)]
pub struct ReviewItem {
    title: String,
    description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeminiReponse {
    pub candidates: Vec<Candidates>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Candidates {
    pub content: Content,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Content {
    pub parts: Vec<Parts>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Parts {
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnimeLink {
    pub title: Option<String>,
    #[serde(rename(serialize = "malId", deserialize = "malId"))]
    pub mal_id: Option<String>,
    #[serde(rename(serialize = "anilistId", deserialize = "anilistId"))]
    pub anilist_id: Option<String>,
    #[serde(rename(serialize = "kitsuId", deserialize = "kitsuId"))]
    pub kitsu_id: Option<String>,
    #[serde(rename(serialize = "animePlanet", deserialize = "animePlanet"))]
    pub anime_planet: Option<String>,
}

impl From<HashMap<String, String>> for AnimeLink {
    fn from(map: HashMap<String, String>) -> AnimeLink {
        AnimeLink {
            title: map.get("title").cloned(),
            mal_id: map.get("malId").cloned(),
            anilist_id: map.get("anilistId").cloned(),
            kitsu_id: map.get("kitsuId").cloned(),
            anime_planet: map.get("animePlanet").cloned(),
        }
    }
}