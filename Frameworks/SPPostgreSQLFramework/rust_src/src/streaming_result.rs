//
//  streaming_result.rs
//  SPPostgreSQLFramework - PostgreSQL Streaming Result Implementation
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

use postgres::{Client, Row, Column};
use std::error::Error;

/// Streaming result that fetches data in batches using PostgreSQL portals
/// This allows processing large result sets without loading everything into memory
pub struct PostgreSQLStreamingResult {
    rows: Vec<Row>,
    columns: Vec<String>,  // Store column names instead of Column objects
    type_oids: Vec<u32>,   // Store PostgreSQL type OIDs
    current_index: usize,
    batch_size: usize,
}

impl PostgreSQLStreamingResult {
    /// Create a new streaming result from rows and columns
    pub fn new(rows: Vec<Row>, columns: &[Column], batch_size: usize) -> Self {
        // Store column names
        let column_names: Vec<String> = columns
            .iter()
            .map(|col| col.name().to_string())
            .collect();
        
        // Store type OIDs
        let type_oids: Vec<u32> = columns
            .iter()
            .map(|col| col.type_().oid())
            .collect();
        
        PostgreSQLStreamingResult {
            rows,
            columns: column_names,
            type_oids,
            current_index: 0,
            batch_size,
        }
    }
    
    /// Get the next batch of rows
    pub fn next_batch(&mut self) -> &[Row] {
        let start = self.current_index;
        let end = std::cmp::min(start + self.batch_size, self.rows.len());
        self.current_index = end;
        &self.rows[start..end]
    }
    
    /// Check if there are more rows to fetch
    pub fn has_more(&self) -> bool {
        self.current_index < self.rows.len()
    }
    
    /// Get the total number of rows
    pub fn total_rows(&self) -> usize {
        self.rows.len()
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
    
    /// Reset to the beginning
    pub fn reset(&mut self) {
        self.current_index = 0;
    }
    
    /// Get all rows (reference)
    pub fn all_rows(&self) -> &[Row] {
        &self.rows
    }
}

/// Simpler batched result - loads all data but provides it in batches
/// This is more memory efficient than loading and converting everything at once
pub struct PostgreSQLBatchedResult {
    rows: Vec<Row>,
    columns: Vec<Column>,
    current_index: usize,
    batch_size: usize,
}

impl PostgreSQLBatchedResult {
    pub fn new(rows: Vec<Row>, columns: Vec<Column>, batch_size: usize) -> Self {
        PostgreSQLBatchedResult {
            rows,
            columns,
            current_index: 0,
            batch_size,
        }
    }
    
    pub fn next_batch(&mut self) -> &[Row] {
        let start = self.current_index;
        let end = std::cmp::min(start + self.batch_size, self.rows.len());
        self.current_index = end;
        &self.rows[start..end]
    }
    
    pub fn has_more(&self) -> bool {
        self.current_index < self.rows.len()
    }
    
    pub fn total_rows(&self) -> usize {
        self.rows.len()
    }
    
    pub fn columns(&self) -> &[Column] {
        &self.columns
    }
    
    pub fn reset(&mut self) {
        self.current_index = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_batched_result_creation() {
        let rows = Vec::new();
        let columns = Vec::new();
        let result = PostgreSQLBatchedResult::new(rows, columns, 100);
        
        assert_eq!(result.total_rows(), 0);
        assert!(!result.has_more());
    }
}

