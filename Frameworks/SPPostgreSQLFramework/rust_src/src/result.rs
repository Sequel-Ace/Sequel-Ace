//
//  result.rs
//  SPPostgreSQLFramework - Result Set Implementation
//

use postgres::{Row, Column};
use postgres::types::{FromSql, Type};
use chrono::{NaiveDateTime, NaiveDate, NaiveTime, DateTime, Utc};
use uuid::Uuid;
use serde_json;
use std::error::Error;

/// A wrapper type that accepts ANY PostgreSQL type and converts it to a String.
/// Used for custom types like ENUMs that don't have built-in Rust type mappings.
#[derive(Debug)]
pub struct AnyValue(pub String);

impl<'a> FromSql<'a> for AnyValue {
    fn from_sql(_ty: &Type, raw: &'a [u8]) -> Result<Self, Box<dyn Error + Sync + Send>> {
        match std::str::from_utf8(raw) {
            Ok(s) => Ok(AnyValue(s.to_string())),
            Err(_) => {
                let hex_str: String = raw.iter().map(|b| format!("{:02x}", b)).collect();
                Ok(AnyValue(format!("\\x{}", hex_str)))
            }
        }
    }

    fn accepts(_ty: &Type) -> bool {
        true
    }
}

/// Extract a value from a Row, trying all known PostgreSQL types.
pub fn get_value(row: &Row, col_idx: usize, _column: &Column) -> Option<String> {
    if let Ok(val) = row.try_get::<_, Option<String>>(col_idx) {
        return val;
    }
    if let Ok(val) = row.try_get::<_, Option<Uuid>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<DateTime<Utc>>>(col_idx) {
        return val.map(|v| v.to_rfc3339());
    }
    if let Ok(val) = row.try_get::<_, Option<NaiveDateTime>>(col_idx) {
        return val.map(|v| v.format("%Y-%m-%d %H:%M:%S%.f").to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<NaiveDate>>(col_idx) {
        return val.map(|v| v.format("%Y-%m-%d").to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<NaiveTime>>(col_idx) {
        return val.map(|v| v.format("%H:%M:%S%.f").to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<i16>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<i32>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<i64>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<f32>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<f64>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<bool>>(col_idx) {
        return val.map(|v| if v { "t".to_string() } else { "f".to_string() });
    }
    if let Ok(val) = row.try_get::<_, Option<serde_json::Value>>(col_idx) {
        return val.map(|v| v.to_string());
    }
    if let Ok(val) = row.try_get::<_, Option<AnyValue>>(col_idx) {
        return val.map(|v| v.0);
    }
    None
}

pub struct PostgreSQLResult {
    rows: Vec<Row>,
    field_names: Vec<String>,
    field_type_oids: Vec<u32>,
    affected_rows: u64,
}

impl PostgreSQLResult {
    pub fn from_rows(rows: Vec<Row>) -> Self {
        let (field_names, field_type_oids) = if let Some(first_row) = rows.first() {
            let names: Vec<String> = first_row.columns().iter().map(|col| col.name().to_string()).collect();
            let oids: Vec<u32> = first_row.columns().iter().map(|col| col.type_().oid()).collect();
            (names, oids)
        } else {
            (Vec::new(), Vec::new())
        };
        let row_count = rows.len() as u64;
        PostgreSQLResult { rows, field_names, field_type_oids, affected_rows: row_count }
    }

    pub fn from_command(affected_rows: u64) -> Self {
        PostgreSQLResult { rows: Vec::new(), field_names: Vec::new(), field_type_oids: Vec::new(), affected_rows }
    }

    pub fn from_rows_with_columns(rows: Vec<Row>, columns: &[Column]) -> Self {
        let field_names = columns.iter().map(|col| col.name().to_string()).collect();
        let field_type_oids = columns.iter().map(|col| col.type_().oid()).collect();
        let row_count = rows.len() as u64;
        PostgreSQLResult { rows, field_names, field_type_oids, affected_rows: row_count }
    }

    pub fn affected_rows(&self) -> u64 { self.affected_rows }
    pub fn num_rows(&self) -> usize { self.rows.len() }
    pub fn num_fields(&self) -> usize { self.field_names.len() }
    pub fn field_name(&self, index: usize) -> Option<String> { self.field_names.get(index).cloned() }
    pub fn field_type_oid(&self, index: usize) -> Option<u32> { self.field_type_oids.get(index).copied() }

    pub fn get_value(&self, row: usize, col: usize) -> Option<String> {
        let row_data = self.rows.get(row)?;

        if let Ok(val) = row_data.try_get::<_, Option<String>>(col) { return val; }
        if let Ok(val) = row_data.try_get::<_, Option<Uuid>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<DateTime<Utc>>>(col) { return val.map(|v| v.to_rfc3339()); }
        if let Ok(val) = row_data.try_get::<_, Option<NaiveDateTime>>(col) { return val.map(|v| v.format("%Y-%m-%d %H:%M:%S%.f").to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<NaiveDate>>(col) { return val.map(|v| v.format("%Y-%m-%d").to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<NaiveTime>>(col) { return val.map(|v| v.format("%H:%M:%S%.f").to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<i16>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<i32>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<i64>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<f32>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<f64>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<bool>>(col) { return val.map(|v| if v { "t".to_string() } else { "f".to_string() }); }
        if let Ok(val) = row_data.try_get::<_, Option<serde_json::Value>>(col) { return val.map(|v| v.to_string()); }
        if let Ok(val) = row_data.try_get::<_, Option<AnyValue>>(col) { return val.map(|v| v.0); }
        None
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

    #[test]
    fn test_command_result() {
        let result = PostgreSQLResult::from_command(5);
        assert_eq!(result.affected_rows(), 5);
        assert_eq!(result.num_rows(), 0);
    }
}
