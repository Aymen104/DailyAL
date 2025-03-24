use config::Config;
use dotenv::dotenv;
use reqwest;

mod anime_service;
mod auth;
mod config;
mod handlers;
mod model;
mod routes;
mod mal_api;
mod model_dto;
mod cache_service;
mod file_storage_service;
mod image_service;
mod gemini_api;

pub struct AppState {
    pub config: Config,
    pub image_service: image_service::ImageService,
    pub anime_service: anime_service::AnimeService,
}

#[tokio::main]
async fn main() {
    dotenv().ok();

    let config = Config::init();
    let app = routes::setup_app(config.await).await;

    let port = std::env::var("PORT").unwrap_or_else(|_| "8001".to_string());
    let addr = format!("0.0.0.0:{}", port);

    println!("Server started at http://{}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
