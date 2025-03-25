use std::sync::Arc;

use config::Config;
use dotenv::dotenv;
use futures::lock::Mutex;
use migrate_anime_link::MigrateAnimeLink;
use reqwest;
use tokio_cron_scheduler::{Job, JobScheduler};

mod anime_service;
mod auth;
mod cache_service;
mod config;
mod file_storage_service;
mod gemini_api;
mod handlers;
mod image_service;
mod mal_api;
mod migrate_anime_link;
mod model;
mod model_dto;
mod routes;

pub struct AppState {
    pub config: Config,
    pub image_service: image_service::ImageService,
    pub anime_service: anime_service::AnimeService,
}

#[tokio::main]
async fn main() {
    dotenv().ok();

    let config = Config::init().await;
    let app = routes::setup_app(config.clone()).await;

    let port = std::env::var("PORT").unwrap_or_else(|_| "8001".to_string());
    let addr = format!("0.0.0.0:{}", port);

    println!("Server started at http://{}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    run_schedulers(config).await;
    axum::serve(listener, app).await.unwrap();
}

async fn run_schedulers(config: Config) -> () {
    let mut sched = JobScheduler::new().await.unwrap();
    let cache_service = cache_service::CacheService {
        config: config.clone(),
    };
    let migrate_anime_link = MigrateAnimeLink {
        config: config.clone(),
        cache_service,
    };
    let mutex = Arc::new(Mutex::new(migrate_anime_link));
    // Run every Sunday at midnight (00:00:00)
    sched
        .add(
            Job::new_async("1/59 * * * * *", move |uuid, mut l| {
                let clone = Arc::clone(&mutex);
                Box::pin(async move {
                    println!("Weekly job running");
                    // Run the migration
                    let migrate_anime_link = clone.lock().await;
                    let _ = migrate_anime_link.start_migration().await;

                    // Query the next execution time for this job
                    let next_tick = l.next_tick_for_job(uuid).await;
                    match next_tick {
                        Ok(Some(ts)) => println!("Next weekly run scheduled for {:?}", ts),
                        _ => println!("Could not get next tick for weekly job"),
                    }
                })
            })
            .unwrap(),
        )
        .await
        .unwrap();

    sched.shutdown_on_ctrl_c();
    sched.set_shutdown_handler(Box::new(|| {
        Box::pin(async move {
            println!("Shut down done");
        })
    }));
    // Start the scheduler
    sched.start().await.unwrap();
}
