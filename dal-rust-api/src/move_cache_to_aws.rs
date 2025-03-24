use crate::config::Config;
use aws_sdk_dynamodb::types::AttributeValue;
use futures::{stream, StreamExt};
use redis::{AsyncCommands, JsonAsyncCommands};

#[derive(Debug, Clone)]
pub struct MoveToAWSService {
    pub config: Config,
}

impl MoveToAWSService {
    async fn get_connection(&self) -> redis::aio::MultiplexedConnection {
        let client = redis::Client::open(self.config.secrets.rediscloud_url.to_string()).unwrap();
        return client.get_multiplexed_async_connection().await.unwrap();
    }
    

    fn add_ttl_in_secs_to_current_time(&self, ttl: i64) -> i64 {
        let current_time = chrono::Utc::now().timestamp();
        return current_time + ttl;
    }

    pub async fn move_cache_to_aws(&self) {
        let mut connection = self.get_connection().await;
        let keys: Vec<String> = connection.keys("*").await.unwrap();
        println!("Keys of size: {:?}", keys.len());
        stream::iter(keys)
            .for_each_concurrent(10, |key| async move {
                self.move_key(&key).await;
            })
            .await;
    }

    async fn move_key(&self, key: &String) {
        let mut connection = self.get_connection().await;
        println!("Key: {}", key);
        let result: Result<String, redis::RedisError> = connection.json_get(key.clone(), "$").await;
        let ttl_o: Result<i64, redis::RedisError> = connection.ttl(key.clone()).await;
        let ttl = self.add_ttl_in_secs_to_current_time(ttl_o.unwrap());
        match result {
            Ok(value) => {
                self.move_data(key, ttl, value).await;
            }
            Err(_) => {
                println!("Error getting value from Redis for key: {}", key);
            }
        }
    }

    async fn move_data(&self, key: &String, ttl: i64, value: String) {
        let pk = format!("CACHE#{}", key);
        let result = self
            .config
            .secrets
            .dynamo_db
            .put_item()
            .table_name(self.config.secrets.table_name.clone())
            .item("pk".to_string(), AttributeValue::S(pk))
            .item("sk".to_string(), AttributeValue::S("metadata".to_string()))
            .item("cached_data".to_string(), AttributeValue::S(value))
            .item("ttl".to_string(), AttributeValue::N(ttl.to_string()))
            .send()
            .await;
        match result {
            Ok(_) => {
                println!("Successfully moved key: {} to AWS DynamoDB", key);
            }
            Err(_) => {
                println!("Error moving key: {} to AWS DynamoDB", key);
            }
        }
    }
}
