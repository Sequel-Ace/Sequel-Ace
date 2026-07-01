//
//  streaming_result.rs
//  SPPostgreSQLFramework - Cursor-based streaming result implementation
//

use postgres::{Client, Row};
use std::error::Error;
use crate::result::AnyValue;
use chrono::{DateTime, Utc, NaiveDateTime, NaiveDate, NaiveTime};
use uuid::Uuid;
use serde_json;

/// TRUE streaming result using PostgreSQL server-side cursors.
/// Only the current batch is in memory; older batches are freed after each fetch.
pub struct PostgreSQLStreamingResult {
    client: *mut Client,
    cursor_name: String,
    columns: Vec<String>,
    type_oids: Vec<u32>,
    total_rows: i64,
    current_batch: Vec<Row>,
    current_batch_start_index: usize,
    batch_size: usize,
    finished: bool,
    owns_transaction: bool,
    client_disconnected: bool,
    cursor_closed: bool,
}

// SAFETY: Client pointer is valid for the lifetime of the connection.
unsafe impl Send for PostgreSQLStreamingResult {}

impl PostgreSQLStreamingResult {
    pub fn new(client: &mut Client, query: &str, batch_size: usize) -> Result<Self, Box<dyn Error>> {
        use std::time::{SystemTime, UNIX_EPOCH};
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_micros();
        let cursor_name = format!("sequel_ace_cursor_{}_{}", std::process::id(), timestamp);

        let owns_transaction = client.execute("BEGIN", &[]).is_ok();

        let declare_sql = format!("DECLARE {} SCROLL CURSOR FOR {}", cursor_name, query);
        if let Err(e) = client.execute(&declare_sql, &[]) {
            if owns_transaction {
                let _ = client.execute("ROLLBACK", &[]);
            }
            return Err(e.into());
        }

        let fetch_meta_sql = format!("FETCH FORWARD 1 FROM {}", cursor_name);
        let rows = match client.query(&fetch_meta_sql, &[]) {
            Ok(rows) => rows,
            Err(e) => {
                let _ = client.execute(&format!("CLOSE {}", cursor_name), &[]);
                if owns_transaction {
                    let _ = client.execute("ROLLBACK", &[]);
                }
                return Err(e.into());
            }
        };

        let (columns, type_oids) = if let Some(first_row) = rows.first() {
            let cols: Vec<String> = first_row.columns().iter().map(|c| c.name().to_string()).collect();
            let oids: Vec<u32> = first_row.columns().iter().map(|c| c.type_().oid()).collect();
            if let Err(e) = client.execute(&format!("MOVE BACKWARD 1 FROM {}", cursor_name), &[]) {
                let _ = client.execute(&format!("CLOSE {}", cursor_name), &[]);
                if owns_transaction {
                    let _ = client.execute("ROLLBACK", &[]);
                }
                return Err(e.into());
            }
            (cols, oids)
        } else {
            let stmt = match client.prepare(&format!(
                "SELECT * FROM ({}) AS meta_query LIMIT 0", query
            )) {
                Ok(s) => s,
                Err(e) => {
                    let _ = client.execute(&format!("CLOSE {}", cursor_name), &[]);
                    if owns_transaction {
                        let _ = client.execute("ROLLBACK", &[]);
                    }
                    return Err(e.into());
                }
            };
            let cols: Vec<String> = stmt.columns().iter().map(|c| c.name().to_string()).collect();
            let oids: Vec<u32> = stmt.columns().iter().map(|c| c.type_().oid()).collect();
            (cols, oids)
        };

        Ok(PostgreSQLStreamingResult {
            client: client as *mut Client,
            cursor_name,
            columns,
            type_oids,
            total_rows: -1,
            current_batch: Vec::new(),
            current_batch_start_index: 0,
            batch_size,
            finished: false,
            owns_transaction,
            client_disconnected: false,
            cursor_closed: false,
        })
    }

    pub fn next_batch(&mut self) -> Result<&[Row], Box<dyn Error>> {
        if self.finished || self.client_disconnected {
            return Ok(&[]);
        }
        unsafe {
            let client = &mut *self.client;
            let fetch_sql = format!("FETCH FORWARD {} FROM {}", self.batch_size, self.cursor_name);
            let rows = client.query(&fetch_sql, &[])?;
            if rows.is_empty() {
                self.finished = true;
                self.current_batch.clear();
                return Ok(&[]);
            }
            self.current_batch_start_index += self.current_batch.len();
            self.current_batch = rows;
            Ok(&self.current_batch)
        }
    }

    pub fn has_more(&self) -> bool { !self.finished }
    pub fn total_rows(&self) -> i64 { self.total_rows }
    pub fn column_names(&self) -> &[String] { &self.columns }
    pub fn num_columns(&self) -> usize { self.columns.len() }
    pub fn type_oid(&self, index: usize) -> Option<u32> { self.type_oids.get(index).copied() }
    pub fn current_batch_size(&self) -> usize { self.current_batch.len() }

    pub fn get_batch_value(&self, batch_relative_row: usize, col: usize) -> Option<String> {
        let row_data = self.current_batch.get(batch_relative_row)?;

        if let Ok(val) = row_data.try_get::<_, Option<String>>(col) { return val; }
        if let Ok(val) = row_data.try_get::<_, Option<Uuid>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<DateTime<Utc>>>(col) { return val.map(|v| v.to_rfc3339()); }
        if let Ok(val) = row_data.try_get::<_, Option<NaiveDateTime>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<NaiveDate>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<NaiveTime>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<i16>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<i32>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<i64>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<f32>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<f64>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<bool>>(col) { return val.map(|v| if v { "true".to_string() } else { "false".to_string() }); }
        if let Ok(val) = row_data.try_get::<_, Option<serde_json::Value>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<AnyValue>>(col) { return val.map(|v| v.0); }
        None
    }

    pub fn mark_client_disconnected(&mut self) {
        self.client_disconnected = true;
        self.finished = true;
    }

    pub fn close(&mut self) -> Result<(), Box<dyn Error>> {
        if self.cursor_closed || self.client_disconnected || self.client.is_null() {
            return Ok(());
        }
        unsafe {
            let client = &mut *self.client;
            let _ = client.execute(&format!("CLOSE {}", self.cursor_name), &[]);
            if self.owns_transaction {
                let _ = client.execute("COMMIT", &[]);
            }
        }
        self.cursor_closed = true;
        self.finished = true;
        Ok(())
    }
}

impl Drop for PostgreSQLStreamingResult {
    fn drop(&mut self) {
        let _ = self.close();
    }
}
