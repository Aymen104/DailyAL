use std::{
    collections::HashSet,
    hash::{Hash, Hasher},
};

use serde::{Deserialize, Serialize};

use crate::model::{Anime, AnimeLink};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentGraphDTO {
    pub nodes: HashSet<ContentNodeDTO>,
    pub edges: Vec<EdgeDTO>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ContentNodeDTO {
    pub id: i64,
    pub title: String,
    pub main_picture: Option<MainPictureDTO>,
    pub mean: Option<f64>,
    pub media_type: Option<String>,
    pub status: Option<String>,
    pub start_season: Option<SeasonDTO>,
    pub alternative_titles: Option<AlternateTitlesDTO>,
}

impl Eq for ContentNodeDTO {}

impl PartialEq for ContentNodeDTO {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}

impl Hash for ContentNodeDTO {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
    }
}

impl From<Anime> for ContentNodeDTO {
    fn from(anime: Anime) -> Self {
        ContentNodeDTO {
            id: anime.id,
            title: anime.title,
            main_picture: anime.main_picture.map(|main_picture| main_picture.into()),
            mean: anime.mean,
            media_type: anime.media_type,
            status: anime.status,
            start_season: anime.start_season.map(|season| season.into()),
            alternative_titles: anime
                .alternative_titles
                .map(|alternate_titles| alternate_titles.into()),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlternateTitlesDTO {
    pub en: Option<String>,
    pub ja: Option<String>,
}

impl From<crate::model::AlternateTitles> for AlternateTitlesDTO {
    fn from(alternate_titles: crate::model::AlternateTitles) -> Self {
        AlternateTitlesDTO {
            en: alternate_titles.en,
            ja: alternate_titles.ja,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EdgeDTO {
    pub source: i64,
    pub target: i64,
    pub relation_type: RelationTypeDTO,
}

impl From<crate::model::Edge> for EdgeDTO {
    fn from(edge: crate::model::Edge) -> Self {
        EdgeDTO {
            source: edge.source,
            target: edge.target,
            relation_type: edge.relation_type.into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MainPictureDTO {
    pub medium: String,
    pub large: String,
}

impl From<crate::model::MainPicture> for MainPictureDTO {
    fn from(main_picture: crate::model::MainPicture) -> Self {
        MainPictureDTO {
            medium: main_picture.medium,
            large: main_picture.large,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SeasonDTO {
    pub year: i64,
    pub season: String,
}

impl From<crate::model::Season> for SeasonDTO {
    fn from(season: crate::model::Season) -> Self {
        SeasonDTO {
            year: season.year,
            season: season.season,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RelationTypeDTO {
    #[serde(rename(serialize = "sequel", deserialize = "sequel"))]
    Sequel,
    #[serde(rename(serialize = "prequel", deserialize = "prequel"))]
    Prequel,
    #[serde(rename(serialize = "alternative_setting", deserialize = "alternative_setting"))]
    AlternativeSetting,
    #[serde(rename(serialize = "alternative_version", deserialize = "alternative_version"))]
    AlternativeVersion,
    #[serde(rename(serialize = "side_story", deserialize = "side_story"))]
    SideStory,
    #[serde(rename(serialize = "parent_story", deserialize = "parent_story"))]
    ParentStory,
    #[serde(rename(serialize = "summary", deserialize = "summary"))]
    Summary,
    #[serde(rename(serialize = "full_story", deserialize = "full_story"))]
    FullStory,
    #[serde(rename(serialize = "spin_off", deserialize = "spin_off"))]
    SpinOff,
    #[serde(rename(serialize = "character", deserialize = "character"))]
    Character,
    #[serde(rename(serialize = "other", deserialize = "other"))]
    Other,
}

impl From<crate::model::RelationType> for RelationTypeDTO {
    fn from(relation_type: crate::model::RelationType) -> Self {
        match relation_type {
            crate::model::RelationType::Sequel => RelationTypeDTO::Sequel,
            crate::model::RelationType::Prequel => RelationTypeDTO::Prequel,
            crate::model::RelationType::AlternativeSetting => RelationTypeDTO::AlternativeSetting,
            crate::model::RelationType::AlternativeVersion => RelationTypeDTO::AlternativeVersion,
            crate::model::RelationType::SideStory => RelationTypeDTO::SideStory,
            crate::model::RelationType::ParentStory => RelationTypeDTO::ParentStory,
            crate::model::RelationType::Summary => RelationTypeDTO::Summary,
            crate::model::RelationType::FullStory => RelationTypeDTO::FullStory,
            crate::model::RelationType::SpinOff => RelationTypeDTO::SpinOff,
            crate::model::RelationType::Character => RelationTypeDTO::Character,
            crate::model::RelationType::Other => RelationTypeDTO::Other,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnimeLinkDTO {
    pub title: Option<String>,
    pub picture: Option<String>,
    pub year: Option<String>,
    #[serde(rename(serialize = "malId", deserialize = "malId"))]
    pub mal_id: Option<String>,
    #[serde(rename(serialize = "anilistId", deserialize = "anilistId"))]
    pub anilist_id: Option<String>,
    #[serde(rename(serialize = "kitsuId", deserialize = "kitsuId"))]
    pub kitsu_id: Option<String>,
    #[serde(rename(serialize = "animePlanet", deserialize = "animePlanet"))]
    pub anime_planet: Option<String>,
}

impl From<AnimeLink> for AnimeLinkDTO {
    fn from(anime: AnimeLink) -> Self {
        AnimeLinkDTO {
            title: anime.title,
            anilist_id: anime.anilist_id,
            mal_id: anime.mal_id,
            kitsu_id: anime.kitsu_id,
            anime_planet: anime.anime_planet,
            picture: anime.picture,
            year: anime.year,
        }
    }
}
