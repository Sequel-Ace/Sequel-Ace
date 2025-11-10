//
//  streaming_result.rs
//  SPPostgreSQLFramework - PostgreSQL TRUE Streaming Result Implementation
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//
//  Implements cursor-based streaming for memory-efficient processing of large result sets
//

use postgres::{Client, Row};
use std::error::Error;

/// TRUE streaming result using PostgreSQL cursors
/// Only keeps current batch in memory, fetches on-demand from server
pub struct PostgreSQLStreamingResult {
    client: *mut Client,  // Raw pointer to client (managed by connection)
    cursor_name: String,
    columns: Vec<String>,
    type_oids: Vec<u32>,
    total_rows: i64,  // -1 if unknown, otherwise actual count
    current_batch: Vec<Row>,
    current_batch_start_index: usize,
    batch_size: usize,
    finished: bool,
    owns_transaction: bool,  // Track if WE started the transaction
    client_disconnected: bool,  // Track if client was disconnected (for safe cleanup)
    cursor_closed: bool,  // Track if cursor has been closed (to avoid double-close)
}

// SAFETY: We ensure Client is only accessed through controlled FFI
unsafe impl Send for PostgreSQLStreamingResult {}

impl PostgreSQLStreamingResult {
    /// Create a new cursor-based streaming result
    /// This executes DECLARE CURSOR and prepares for batch fetching
    pub fn new(
        client: &mut Client,
        query: &str,
        batch_size: usize,
    ) -> Result<Self, Box<dyn Error>> {
        // Generate unique cursor name with timestamp for uniqueness across multiple cursors
        use std::time::{SystemTime, UNIX_EPOCH};
        let timestamp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_micros();
        let cursor_name = format!("sequel_ace_cursor_{}_{}", std::process::id(), timestamp);
        
        // Try to start a transaction (required for cursors)
        // Track if WE started it so we know whether to commit/rollback later
        let owns_transaction = match client.execute("BEGIN", &[]) {
            Ok(_) => true,   // We started the transaction
            Err(_) => false, // Already in transaction
        };
        
        // Declare cursor with the query
        let declare_sql = format!("DECLARE {} SCROLL CURSOR FOR {}", cursor_name, query);
        client.execute(&declare_sql, &[])?;
        
        // Fetch first row to get column metadata (without moving cursor forward significantly)
        let fetch_meta_sql = format!("FETCH FORWARD 1 FROM {}", cursor_name);
        let rows = client.query(&fetch_meta_sql, &[])?;
        
        // Extract column metadata from the statement, not the rows
        // This works even for empty result sets!
        let (columns, type_oids) = if let Some(first_row) = rows.first() {
            let cols: Vec<String> = first_row
                .columns()
                .iter()
                .map(|col| col.name().to_string())
                .collect();
            
            let oids: Vec<u32> = first_row
                .columns()
                .iter()
                .map(|col| col.type_().oid())
                .collect();
            
            // Move cursor back to start since we fetched one row for metadata
            client.execute(&format!("MOVE BACKWARD 1 FROM {}", cursor_name), &[])?;
            
            (cols, oids)
        } else {
            // Empty result set - we still need column metadata!
            // Use a prepared statement to get column info without fetching rows
            let stmt = client.prepare(&format!("SELECT * FROM ({}) AS meta_query LIMIT 0", query))?;
            let cols: Vec<String> = stmt
                .columns()
                .iter()
                .map(|col| col.name().to_string())
                .collect();
            
            let oids: Vec<u32> = stmt
                .columns()
                .iter()
                .map(|col| col.type_().oid())
                .collect();
            
            (cols, oids)
        };
        
        // Total rows are unknown for cursor-based streaming
        // They will be determined after all batches are fetched (like MySQL's mysql_use_result)
        let total_rows = -1;
        
        Ok(PostgreSQLStreamingResult {
            client: client as *mut Client,
            cursor_name,
            columns,
            type_oids,
            total_rows,
            current_batch: Vec::new(),
            current_batch_start_index: 0,
            batch_size,
            finished: false,
            owns_transaction,
            client_disconnected: false,
            cursor_closed: false,
        })
    }
    
    /// Get the next batch of rows from the cursor
    pub fn next_batch(&mut self) -> Result<&[Row], Box<dyn Error>> {
        if self.finished || self.client_disconnected {
            return Ok(&[]);
        }
        
        // SAFETY: Client pointer is valid as long as connection is alive
        unsafe {
            let client = &mut *self.client;
            
            // Fetch next batch from cursor
            let fetch_sql = format!("FETCH FORWARD {} FROM {}", self.batch_size, self.cursor_name);
            let rows = client.query(&fetch_sql, &[])?;
            
            if rows.is_empty() {
                self.finished = true;
                self.current_batch.clear();
                return Ok(&[]);
            }
            
            // Update batch start index
            self.current_batch_start_index += self.current_batch.len();
            
            // Replace current batch (frees old batch from memory!)
            self.current_batch = rows;
            
            Ok(&self.current_batch)
        }
    }
    
    /// Check if there are more rows to fetch
    pub fn has_more(&self) -> bool {
        !self.finished
    }
    
    /// Get the total number of rows (may be -1 if unknown)
    pub fn total_rows(&self) -> i64 {
        self.total_rows
    }
    
    /// Get column names
    pub fn column_names(&self) -> &[String] {
        &self.columns
    }
    
    /// Get number of columns
    pub fn num_columns(&self) -> usize {
        self.columns.len()
    }
    
    /// Get type OID for a column
    pub fn type_oid(&self, index: usize) -> Option<u32> {
        self.type_oids.get(index).copied()
    }
    
    /// Get value from current batch at relative index
    /// Returns None if index is out of range for current batch
    pub fn get_batch_value(&self, batch_relative_row: usize, col: usize) -> Option<String> {
        use chrono::{DateTime, Utc, NaiveDateTime, NaiveDate, NaiveTime};
        use uuid::Uuid;
        
        if let Some(row_data) = self.current_batch.get(batch_relative_row) {
            // Try string first (TEXT, VARCHAR, etc.)
            if let Ok(val) = row_data.try_get::<_, Option<String>>(col) {
                return val;
            }
            
            // Try UUID
            if let Ok(val) = row_data.try_get::<_, Option<Uuid>>(col) {
                return val.map(|v| v.to_string());
            }
            
            // Try timestamp with timezone (TIMESTAMPTZ)
            if let Ok(val) = row_data.try_get::<_, Option<DateTime<Utc>>>(col) {
                return val.map(|v| v.to_rfc3339());
            }
            
            // Try timestamp without timezone (TIMESTAMP)
            if let Ok(val) = row_data.try_get::<_, Option<NaiveDateTime>>(col) {
                return val.map(|v| v.to_string());
            }
            
            // Try date (DATE)
            if let Ok(val) = row_data.try_get::<_, Option<NaiveDate>>(col) {
                return val.map(|v| v.to_string());
            }
            
            // Try time (TIME)
            if let Ok(val) = row_data.try_get::<_, Option<NaiveTime>>(col) {
                return val.map(|v| v.to_string());
            }
            
            // Try numeric types
            if let Ok(val) = row_data.try_get::<_, Option<i16>>(col) {
                return val.map(|v| v.to_string());
            }
            
            if let Ok(val) = row_data.try_get::<_, Option<i32>>(col) {
                return val.map(|v| v.to_string());
            }
            
            if let Ok(val) = row_data.try_get::<_, Option<i64>>(col) {
                return val.map(|v| v.to_string());
            }
            
            if let Ok(val) = row_data.try_get::<_, Option<f32>>(col) {
                return val.map(|v| v.to_string());
            }
            
            if let Ok(val) = row_data.try_get::<_, Option<f64>>(col) {
                return val.map(|v| v.to_string());
            }
            
            // Try boolean
            if let Ok(val) = row_data.try_get::<_, Option<bool>>(col) {
                return val.map(|v| if v { "true".to_string() } else { "false".to_string() });
            }
            
            // Try JSON/JSONB
            if let Ok(val) = row_data.try_get::<_, Option<serde_json::Value>>(col) {
                return val.map(|v| v.to_string());
            }
        }
        
        None
    }
    
    /// Get current batch size
    pub fn current_batch_size(&self) -> usize {
        self.current_batch.len()
    }
    
    /// Mark the client as disconnected (called when connection is closed)
    /// This prevents trying to close cursor on an invalid client
    pub fn mark_client_disconnected(&mut self) {
        self.client_disconnected = true;
        self.finished = true;
    }
    
    /// Close the cursor and clean up
    pub fn close(&mut self) -> Result<(), Box<dyn Error>> {
        // Skip if already closed, client disconnected, or client null
        if self.cursor_closed || self.client_disconnected || self.client.is_null() {
            return Ok(());
        }
        
        // Close cursor and commit transaction even if finished=true
        // (finished just means we fetched all rows, we still need to clean up!)
        unsafe {
            let client = &mut *self.client;
            
            // Close cursor
            let close_sql = format!("CLOSE {}", self.cursor_name);
            let _ = client.execute(&close_sql, &[]);
            
            // Only commit if WE started the transaction
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
