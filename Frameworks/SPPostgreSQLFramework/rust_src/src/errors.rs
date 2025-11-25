//
//  errors.rs
//  SPPostgreSQLFramework - Error Handling
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

use std::fmt;
use std::error::Error;

#[derive(Debug)]
pub enum PostgreSQLError {
    NotConnected,
    ConnectionFailed(String),
    QueryFailed(String),
    InvalidParameter(String),
}

impl fmt::Display for PostgreSQLError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            PostgreSQLError::NotConnected => {
                write!(f, "Not connected to PostgreSQL server")
            },
            PostgreSQLError::ConnectionFailed(msg) => {
                write!(f, "Connection failed: {}", msg)
            },
            PostgreSQLError::QueryFailed(msg) => {
                write!(f, "Query failed: {}", msg)
            },
            PostgreSQLError::InvalidParameter(msg) => {
                write!(f, "Invalid parameter: {}", msg)
            },
        }
    }
}

impl Error for PostgreSQLError {}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_error_display() {
        let err = PostgreSQLError::NotConnected;
        assert_eq!(err.to_string(), "Not connected to PostgreSQL server");
    }
}

