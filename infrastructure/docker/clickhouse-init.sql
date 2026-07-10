-- VTO ClickHouse initialization
-- Creates the events table and daily aggregates materialized view.

CREATE DATABASE IF NOT EXISTS analytics;

USE analytics;

CREATE TABLE IF NOT EXISTS events (
    event_id String,
    event_type LowCardinality(String),
    retailer_id String,
    shopper_token_id String,
    session_id String,
    tryon_id String,
    garment_sku String,
    body_profile_id String,
    device_platform LowCardinality(String),
    device_os_version String,
    app_version String,
    locale LowCardinality(String),
    timestamp DateTime64(3, 'UTC'),
    custom_attributes String,
    ingested_at DateTime64(3, 'UTC') DEFAULT now64()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (retailer_id, timestamp, event_type)
TTL timestamp + INTERVAL 13 MONTH;

CREATE MATERIALIZED VIEW IF NOT EXISTS daily_aggregates
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (retailer_id, date, event_type)
AS
SELECT
    retailer_id,
    toDate(timestamp) AS date,
    event_type,
    count() AS event_count
FROM events
GROUP BY retailer_id, date, event_type;

CREATE MATERIALIZED VIEW IF NOT EXISTS tryon_funnel
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(date)
ORDER BY (retailer_id, date)
AS
SELECT
    retailer_id,
    toDate(timestamp) AS date,
    countIf(event_type = 'tryon_button_shown') AS button_shown,
    countIf(event_type = 'tryon_button_tapped') AS button_tapped,
    countIf(event_type = 'scan_started') AS scan_started,
    countIf(event_type = 'scan_completed') AS scan_completed,
    countIf(event_type = 'tryon_succeeded') AS tryon_succeeded,
    countIf(event_type = 'tryon_viewed') AS tryon_viewed,
    countIf(event_type = 'add_to_cart_after_tryon') AS add_to_cart,
    countIf(event_type = 'purchase_after_tryon') AS purchase
FROM events
GROUP BY retailer_id, date;
