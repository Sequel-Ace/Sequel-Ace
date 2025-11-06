//
//  connection.rs
//  SPPostgreSQLFramework - PostgreSQL Connection Implementation
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

use postgres::{Client, NoTls, Config};
use postgres_native_tls::MakeTlsConnector;
use native_tls::TlsConnector;
use std::error::Error;
use crate::result::PostgreSQLResult;
use crate::errors::PostgreSQLError;
use crate::streaming_result::PostgreSQLStreamingResult;

pub struct PostgreSQLConnection {
    client: Option<Client>,
    last_error: Option<String>,
    config: Config,
}

impl PostgreSQLConnection {
    pub fn new() -> Self {
        PostgreSQLConnection {
            client: None,
            last_error: None,
            config: Config::new(),
        }
    }
    
    pub fn connect(
        &mut self,
        host: &str,
        port: u16,
        username: &str,
        password: &str,
        database: &str,
        use_ssl: bool,
    ) -> Result<(), Box<dyn Error>> {
        // Build connection configuration
        self.config.host(host);
        self.config.port(port);
        self.config.user(username);
        self.config.password(password);
        self.config.dbname(database);
        
        // Connect with or without TLS based on use_ssl flag
        let result = if use_ssl {
            // Create a TLS connector that accepts invalid certificates
            // This is useful for development and self-signed certificates
            let connector = TlsConnector::builder()
                .danger_accept_invalid_certs(true)
                .danger_accept_invalid_hostnames(true)
                .build()?;
            
            let tls = MakeTlsConnector::new(connector);
            self.config.connect(tls)
        } else {
            self.config.connect(NoTls)
        };
        
        match result {
            Ok(client) => {
                self.client = Some(client);
                self.last_error = None;
                Ok(())
            },
            Err(e) => {
                self.last_error = Some(e.to_string());
                Err(Box::new(e))
            }
        }
    }
    
    pub fn disconnect(&mut self) {
        self.client = None;
        self.last_error = None;
    }
    
    pub fn is_connected(&self) -> bool {
        self.client.is_some()
    }
    
    pub fn execute_query(&mut self, query: &str) -> Result<PostgreSQLResult, Box<dyn Error>> {
        match &mut self.client {
            Some(client) => {
                // Determine if this is a command (UPDATE/DELETE/INSERT) or a query (SELECT)
                let trimmed = query.trim_start().to_uppercase();
                let is_command = trimmed.starts_with("UPDATE") || 
                                 trimmed.starts_with("DELETE") || 
                                 trimmed.starts_with("INSERT");
                
                if is_command {
                    // For commands, use execute() to get affected rows
                    match client.execute(query, &[]) {
                        Ok(affected_rows) => {
                            self.last_error = None;
                            Ok(PostgreSQLResult::from_command(affected_rows))
                        },
                        Err(e) => {
                            self.last_error = Some(e.to_string());
                            Err(Box::new(e))
                        }
                    }
                } else {
                    // For queries, use prepared statement to preserve column metadata even for empty results
                    match client.prepare(query) {
                        Ok(statement) => {
                            match client.query(&statement, &[]) {
                                Ok(rows) => {
                                    self.last_error = None;
                                    // Pass column information from the statement
                                    Ok(PostgreSQLResult::from_rows_with_columns(rows, statement.columns()))
                                },
                                Err(e) => {
                                    self.last_error = Some(e.to_string());
                                    Err(Box::new(e))
                                }
                            }
                        },
                        Err(e) => {
                            self.last_error = Some(e.to_string());
                            Err(Box::new(e))
                        }
                    }
                }
            },
            None => {
                let error = PostgreSQLError::NotConnected;
                self.last_error = Some(error.to_string());
                Err(Box::new(error))
            }
        }
    }
    
    /// Execute a streaming query that loads data in batches
    /// This is more memory efficient for large result sets
    /// batch_size: number of rows to process at a time (default: 1000)
    pub fn execute_streaming_query(&mut self, query: &str, batch_size: usize) 
        -> Result<PostgreSQLStreamingResult, Box<dyn Error>> {
        
        match &mut self.client {
            Some(client) => {
                // Use prepared statement to preserve column metadata
                match client.prepare(query) {
                    Ok(statement) => {
                        let columns = statement.columns();
                        
                        match client.query(&statement, &[]) {
                            Ok(rows) => {
                                self.last_error = None;
                                // Return streaming result for efficient processing
                                Ok(PostgreSQLStreamingResult::new(rows, columns, batch_size))
                            },
                            Err(e) => {
                                self.last_error = Some(e.to_string());
                                Err(Box::new(e))
                            }
                        }
                    },
                    Err(e) => {
                        self.last_error = Some(e.to_string());
                        Err(Box::new(e))
                    }
                }
            },
            None => {
                let error = PostgreSQLError::NotConnected;
                self.last_error = Some(error.to_string());
                Err(Box::new(error))
            }
        }
    }
    
    pub fn execute_update(&mut self, query: &str) -> Result<u64, Box<dyn Error>> {
        match &mut self.client {
            Some(client) => {
                match client.execute(query, &[]) {
                    Ok(rows_affected) => {
                        self.last_error = None;
                        Ok(rows_affected)
                    },
                    Err(e) => {
                        self.last_error = Some(e.to_string());
                        Err(Box::new(e))
                    }
                }
            },
            None => {
                let error = PostgreSQLError::NotConnected;
                self.last_error = Some(error.to_string());
                Err(Box::new(error))
            }
        }
    }
    
    pub fn list_databases(&mut self) -> Result<Vec<String>, Box<dyn Error>> {
        let query = "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname";
        
        match &mut self.client {
            Some(client) => {
                match client.query(query, &[]) {
                    Ok(rows) => {
                        let databases: Vec<String> = rows
                            .iter()
                            .filter_map(|row| row.try_get::<_, String>(0).ok())
                            .collect();
                        Ok(databases)
                    },
                    Err(e) => {
                        self.last_error = Some(e.to_string());
                        Err(Box::new(e))
                    }
                }
            },
            None => {
                let error = PostgreSQLError::NotConnected;
                self.last_error = Some(error.to_string());
                Err(Box::new(error))
            }
        }
    }
    
    pub fn list_schemas(&mut self) -> Result<Vec<String>, Box<dyn Error>> {
        let query = "SELECT schema_name FROM information_schema.schemata \
                     WHERE schema_name NOT IN ('pg_catalog', 'information_schema') \
                     ORDER BY schema_name";
        
        match &mut self.client {
            Some(client) => {
                match client.query(query, &[]) {
                    Ok(rows) => {
                        let schemas: Vec<String> = rows
                            .iter()
                            .filter_map(|row| row.try_get::<_, String>(0).ok())
                            .collect();
                        Ok(schemas)
                    },
                    Err(e) => {
                        self.last_error = Some(e.to_string());
                        Err(Box::new(e))
                    }
                }
            },
            None => {
                let error = PostgreSQLError::NotConnected;
                self.last_error = Some(error.to_string());
                Err(Box::new(error))
            }
        }
    }
    
    pub fn list_tables(&mut self, schema: &str) -> Result<Vec<String>, Box<dyn Error>> {
        let query = format!(
            "SELECT tablename FROM pg_tables WHERE schemaname = '{}' ORDER BY tablename",
            schema.replace("'", "''")
        );
        
        match &mut self.client {
            Some(client) => {
                match client.query(&query, &[]) {
                    Ok(rows) => {
                        let tables: Vec<String> = rows
                            .iter()
                            .filter_map(|row| row.try_get::<_, String>(0).ok())
                            .collect();
                        Ok(tables)
                    },
                    Err(e) => {
                        self.last_error = Some(e.to_string());
                        Err(Box::new(e))
                    }
                }
            },
            None => {
                let error = PostgreSQLError::NotConnected;
                self.last_error = Some(error.to_string());
                Err(Box::new(error))
            }
        }
    }
    
    pub fn escape_string(&self, input: &str) -> String {
        // Simple SQL string escaping - double single quotes
        input.replace("'", "''")
    }
    
    pub fn last_error(&self) -> Option<String> {
        self.last_error.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_connection_creation() {
        let conn = PostgreSQLConnection::new();
        assert!(!conn.is_connected());
    }
    
    #[test]
    fn test_escape_string() {
        let conn = PostgreSQLConnection::new();
        let escaped = conn.escape_string("It's a test");
        assert_eq!(escaped, "It''s a test");
    }
}

