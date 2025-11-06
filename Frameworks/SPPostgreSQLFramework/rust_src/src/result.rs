//
//  result.rs
//  SPPostgreSQLFramework - Result Set Implementation
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

use postgres::{Row, Column};
use chrono::{NaiveDateTime, NaiveDate, NaiveTime, DateTime, Utc};
use uuid::Uuid;
use serde_json;

/// Standalone function to extract a value from a Row
/// Used by both regular and streaming results
pub fn get_value(row: &Row, col_idx: usize, _column: &Column) -> Option<String> {
    // Try string first (TEXT, VARCHAR, etc.)
    if let Ok(val) = row.try_get::<_, Option<String>>(col_idx) {
        return val;
    }
    
    // Try UUID
    if let Ok(val) = row.try_get::<_, Option<Uuid>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    
    // Try timestamp with timezone (TIMESTAMPTZ)
    if let Ok(val) = row.try_get::<_, Option<DateTime<Utc>>>(col_idx) {
        return val.map(|v| v.to_rfc3339());
    }
    
    // Try timestamp without timezone (TIMESTAMP)
    if let Ok(val) = row.try_get::<_, Option<NaiveDateTime>>(col_idx) {
        return val.map(|v| v.format("%Y-%m-%d %H:%M:%S%.f").to_string());
    }
    
    // Try date (DATE)
    if let Ok(val) = row.try_get::<_, Option<NaiveDate>>(col_idx) {
        return val.map(|v| v.format("%Y-%m-%d").to_string());
    }
    
    // Try time (TIME)
    if let Ok(val) = row.try_get::<_, Option<NaiveTime>>(col_idx) {
        return val.map(|v| v.format("%H:%M:%S%.f").to_string());
    }
    
    
    // Try integer types
    if let Ok(val) = row.try_get::<_, Option<i16>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    
    if let Ok(val) = row.try_get::<_, Option<i32>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    
    if let Ok(val) = row.try_get::<_, Option<i64>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    
    // Try floating point types
    if let Ok(val) = row.try_get::<_, Option<f32>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    
    if let Ok(val) = row.try_get::<_, Option<f64>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    
    // Try bool
    if let Ok(val) = row.try_get::<_, Option<bool>>(col_idx) {
        return val.map(|v| if v { "t".to_string() } else { "f".to_string() });
    }
    
    // Try JSON/JSONB
    if let Ok(val) = row.try_get::<_, Option<serde_json::Value>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    
    // If all else fails, return None (NULL value)
    None
}

pub struct PostgreSQLResult {
    rows: Vec<Row>,
    field_names: Vec<String>,
    field_type_oids: Vec<u32>,  // Store PostgreSQL type OIDs
    affected_rows: u64,  // Number of rows affected by UPDATE/DELETE/INSERT
}

impl PostgreSQLResult {
    pub fn from_rows(rows: Vec<Row>) -> Self {
        let (field_names, field_type_oids) = if let Some(first_row) = rows.first() {
            let names: Vec<String> = first_row
                .columns()
                .iter()
                .map(|col| col.name().to_string())
                .collect();
            
            let oids: Vec<u32> = first_row
                .columns()
                .iter()
                .map(|col| col.type_().oid())
                .collect();
            
            (names, oids)
        } else {
            (Vec::new(), Vec::new())
        };
        
        let row_count = rows.len() as u64;
        
        PostgreSQLResult {
            rows,
            field_names,
            field_type_oids,
            affected_rows: row_count,
        }
    }
    
    pub fn from_command(affected_rows: u64) -> Self {
        // For UPDATE/DELETE/INSERT commands that don't return rows
        PostgreSQLResult {
            rows: Vec::new(),
            field_names: Vec::new(),
            field_type_oids: Vec::new(),
            affected_rows,
        }
    }
    
    pub fn from_rows_with_columns(rows: Vec<Row>, columns: &[Column]) -> Self {
        let field_names = columns
            .iter()
            .map(|col| col.name().to_string())
            .collect();
        
        let field_type_oids = columns
            .iter()
            .map(|col| col.type_().oid())
            .collect();
        
        let row_count = rows.len() as u64;
        
        PostgreSQLResult {
            rows,
            field_names,
            field_type_oids,
            affected_rows: row_count,
        }
    }
    
    pub fn affected_rows(&self) -> u64 {
        self.affected_rows
    }
    
    pub fn num_rows(&self) -> usize {
        self.rows.len()
    }
    
    pub fn num_fields(&self) -> usize {
        self.field_names.len()
    }
    
    pub fn field_name(&self, index: usize) -> Option<String> {
        self.field_names.get(index).cloned()
    }
    
    pub fn field_type_oid(&self, index: usize) -> Option<u32> {
        self.field_type_oids.get(index).copied()
    }
    
    pub fn get_value(&self, row: usize, col: usize) -> Option<String> {
        if let Some(row_data) = self.rows.get(row) {
            // Try to get the value as various PostgreSQL types and convert to string
            
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
                return val.map(|v| v.format("%Y-%m-%d %H:%M:%S%.f").to_string());
            }
            
            // Try date (DATE)
            if let Ok(val) = row_data.try_get::<_, Option<NaiveDate>>(col) {
                return val.map(|v| v.format("%Y-%m-%d").to_string());
            }
            
            // Try time (TIME)
            if let Ok(val) = row_data.try_get::<_, Option<NaiveTime>>(col) {
                return val.map(|v| v.format("%H:%M:%S%.f").to_string());
            }
            
            
            // Try integer types
            if let Ok(val) = row_data.try_get::<_, Option<i16>>(col) {
                return val.map(|v| v.to_string());
            }
            
            if let Ok(val) = row_data.try_get::<_, Option<i32>>(col) {
                return val.map(|v| v.to_string());
            }
            
            if let Ok(val) = row_data.try_get::<_, Option<i64>>(col) {
                return val.map(|v| v.to_string());
            }
            
            // Try floating point types
            if let Ok(val) = row_data.try_get::<_, Option<f32>>(col) {
                return val.map(|v| v.to_string());
            }
            
            if let Ok(val) = row_data.try_get::<_, Option<f64>>(col) {
                return val.map(|v| v.to_string());
            }
            
            // Try bool
            if let Ok(val) = row_data.try_get::<_, Option<bool>>(col) {
                return val.map(|v| if v { "t".to_string() } else { "f".to_string() });
            }
            
            // Try JSON/JSONB (as serde_json::Value)
            if let Ok(val) = row_data.try_get::<_, Option<serde_json::Value>>(col) {
                return val.map(|v| v.to_string());
            }
            
            // If we can't get the value, return None (NULL)
            None
        } else {
            None
        }
    }
    
    pub fn get_row(&self, index: usize) -> Option<Vec<Option<String>>> {
        if index < self.rows.len() {
            let mut values = Vec::new();
            for col in 0..self.num_fields() {
                values.push(self.get_value(index, col));
            }
            Some(values)
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_empty_result() {
        let result = PostgreSQLResult::from_rows(Vec::new());
        assert_eq!(result.num_rows(), 0);
        assert_eq!(result.num_fields(), 0);
    }
}

