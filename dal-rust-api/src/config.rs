use aws_config::{meta::region::RegionProviderChain, Region};

#[derive(Debug, Clone)]
pub struct Secrets {
    pub mal_client_id: String,
    pub bearer_secret: String,
    pub rediscloud_url: String,
    pub subastorage_url: String,
    pub subastorage_key: String,
    pub gemini_api_key: String,
    pub dynamo_db: aws_sdk_dynamodb::Client,
    pub table_name: String,
}

#[derive(Debug, Clone)]
pub struct Config {
    pub base_url: String,
    pub secrets: Secrets,
}

impl Config {
    pub async fn init() -> Config {
        let bearer_secret = std::env::var("BEARER_SECRET").expect("BEARER_SECRET must be set");
        let mal_client_id = std::env::var("MAL_CLIENT_ID").expect("missing MAL_CLIENT_ID");
        let base_url = std::env::var("BASE_URL").expect("missing BASE_URL");
        let rediscloud_url = std::env::var("REDISCLOUD_URL").expect("missing REDISCLOUD_URL");
        let subastorage_url =
            std::env::var("SUPABASE_URL_STORAGE").expect("missing SUPABASE_URL_STORAGE");
        let subastorage_key = std::env::var("SUPABASE_API_KEY").expect("missing SUPABASE_API_KEY");
        let gemini_api_key = std::env::var("GEMINI_API_KEY").expect("missing GEMINI_API_KEY");
        let region = std::env::var("REGION");
        let region_provider = RegionProviderChain::first_try(region.map(Region::new).ok())
            .or_default_provider()
            .or_else(Region::new("us-east-1"));
        let shared_config = aws_config::from_env().region(region_provider).load().await;
        let dynamo_db = aws_sdk_dynamodb::Client::new(&shared_config);
        let table_name = std::env::var("TABLE_NAME").expect("missing TABLE_NAME");
        let secrets = Secrets {
            mal_client_id,
            bearer_secret,
            rediscloud_url,
            subastorage_url,
            subastorage_key,
            gemini_api_key,
            dynamo_db,
            table_name,
        };

        Config { secrets, base_url }
    }
}
