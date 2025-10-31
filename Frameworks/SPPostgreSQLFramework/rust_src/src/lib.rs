//
//  lib.rs
//  SPPostgreSQLFramework - Rust Implementation
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::error::Error;

mod connection;
mod result;
mod errors;

use connection::PostgreSQLConnection;
use result::PostgreSQLResult;
use errors::PostgreSQLError;

// Opaque types for C API
pub struct SPPostgreSQLConnection {
    inner: PostgreSQLConnection,
}

pub struct SPPostgreSQLResult {
    inner: PostgreSQLResult,
}

// Connection Management

#[no_mangle]
pub extern "C" fn sp_postgresql_connection_create() -> *mut SPPostgreSQLConnection {
    let conn = Box::new(SPPostgreSQLConnection {
        inner: PostgreSQLConnection::new(),
    });
    Box::into_raw(conn)
}

#[no_mangle]
pub extern "C" fn sp_postgresql_connection_destroy(conn: *mut SPPostgreSQLConnection) {
    if !conn.is_null() {
        unsafe {
            let _ = Box::from_raw(conn);
        }
    }
}

#[no_mangle]
pub extern "C" fn sp_postgresql_connection_connect(
    conn: *mut SPPostgreSQLConnection,
    host: *const c_char,
    port: c_int,
    username: *const c_char,
    password: *const c_char,
    database: *const c_char,
    use_ssl: c_int,
) -> c_int {
    if conn.is_null() {
        return 0;
    }
    
    unsafe {
        let conn_ref = &mut (*conn).inner;
        
        let host_str = if !host.is_null() {
            CStr::from_ptr(host).to_string_lossy().into_owned()
        } else {
            "localhost".to_string()
        };
        
        let username_str = if !username.is_null() {
            CStr::from_ptr(username).to_string_lossy().into_owned()
        } else {
            "postgres".to_string()
        };
        
        let password_str = if !password.is_null() {
            CStr::from_ptr(password).to_string_lossy().into_owned()
        } else {
            String::new()
        };
        
        let database_str = if !database.is_null() {
            CStr::from_ptr(database).to_string_lossy().into_owned()
        } else {
            "postgres".to_string()
        };
        
        eprintln!("🦀 Rust: Attempting PostgreSQL connection:");
        eprintln!("   host: {}", host_str);
        eprintln!("   port: {}", port);
        eprintln!("   username: {}", username_str);
        eprintln!("   database: {}", database_str);
        eprintln!("   password: {}", password_str);
        eprintln!("   use_ssl: {}", use_ssl);
        
        match conn_ref.connect(&host_str, port as u16, &username_str, &password_str, &database_str, use_ssl != 0) {
            Ok(_) => {
                eprintln!("🦀 Rust: Connection successful!");
                1
            },
            Err(e) => {
                eprintln!("🦀 Rust: Connection failed!");
                eprintln!("   Error type: {:?}", e);
                eprintln!("   Error message: {}", e);
                // Try to get more details if it's a PostgreSQL error
                if let Some(db_error) = e.downcast_ref::<postgres::Error>() {
                    eprintln!("   PostgreSQL Error Details:");
                    eprintln!("     Code: {:?}", db_error.code());
                    eprintln!("     Message: {}", db_error);
                    if let Some(db_err) = db_error.as_db_error() {
                        eprintln!("     DB Error: {}", db_err.message());
                        eprintln!("     Detail: {:?}", db_err.detail());
                        eprintln!("     Hint: {:?}", db_err.hint());
                    }
                }
                0
            },
        }
    }
}

#[no_mangle]
pub extern "C" fn sp_postgresql_connection_disconnect(conn: *mut SPPostgreSQLConnection) {
    if conn.is_null() {
        return;
    }
    
    unsafe {
        let conn_ref = &mut (*conn).inner;
        conn_ref.disconnect();
    }
}

#[no_mangle]
pub extern "C" fn sp_postgresql_connection_is_connected(conn: *const SPPostgreSQLConnection) -> c_int {
    if conn.is_null() {
        return 0;
    }
    
    unsafe {
        let conn_ref = &(*conn).inner;
        if conn_ref.is_connected() { 1 } else { 0 }
    }
}

// Query Execution

#[no_mangle]
pub extern "C" fn sp_postgresql_connection_execute_query(
    conn: *mut SPPostgreSQLConnection,
    query: *const c_char,
) -> *mut SPPostgreSQLResult {
    if conn.is_null() || query.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let conn_ref = &mut (*conn).inner;
        let query_str = CStr::from_ptr(query).to_string_lossy().into_owned();
        
        match conn_ref.execute_query(&query_str) {
            Ok(result) => {
                let result_box = Box::new(SPPostgreSQLResult {
                    inner: result,
                });
                Box::into_raw(result_box)
            },
            Err(_) => ptr::null_mut(),
        }
    }
}

// Result Management

#[no_mangle]
pub extern "C" fn sp_postgresql_result_destroy(result: *mut SPPostgreSQLResult) {
    if !result.is_null() {
        unsafe {
            let _ = Box::from_raw(result);
        }
    }
}

#[no_mangle]
pub extern "C" fn sp_postgresql_result_num_rows(result: *const SPPostgreSQLResult) -> c_int {
    if result.is_null() {
        return 0;
    }
    
    unsafe {
        let result_ref = &(*result).inner;
        result_ref.num_rows() as c_int
    }
}

#[no_mangle]
pub extern "C" fn sp_postgresql_result_num_fields(result: *const SPPostgreSQLResult) -> c_int {
    if result.is_null() {
        return 0;
    }
    
    unsafe {
        let result_ref = &(*result).inner;
        result_ref.num_fields() as c_int
    }
}

#[no_mangle]
pub extern "C" fn sp_postgresql_result_field_name(
    result: *const SPPostgreSQLResult,
    field_index: c_int,
) -> *mut c_char {
    if result.is_null() || field_index < 0 {
        return ptr::null_mut();
    }
    
    unsafe {
        let result_ref = &(*result).inner;
        match result_ref.field_name(field_index as usize) {
            Some(name) => {
                match CString::new(name) {
                    Ok(c_str) => c_str.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            },
            None => ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn sp_postgresql_result_get_value(
    result: *const SPPostgreSQLResult,
    row: c_int,
    col: c_int,
) -> *mut c_char {
    if result.is_null() || row < 0 || col < 0 {
        return ptr::null_mut();
    }
    
    unsafe {
        let result_ref = &(*result).inner;
        match result_ref.get_value(row as usize, col as usize) {
            Some(value) => {
                match CString::new(value) {
                    Ok(c_str) => c_str.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            },
            None => ptr::null_mut(),
        }
    }
}

// Error Handling

#[no_mangle]
pub extern "C" fn sp_postgresql_connection_last_error(conn: *const SPPostgreSQLConnection) -> *mut c_char {
    if conn.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let conn_ref = &(*conn).inner;
        match conn_ref.last_error() {
            Some(error) => {
                match CString::new(error) {
                    Ok(c_str) => c_str.into_raw(),
                    Err(_) => ptr::null_mut(),
                }
            },
            None => ptr::null_mut(),
        }
    }
}

// Utility Functions

#[no_mangle]
pub extern "C" fn sp_postgresql_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

#[no_mangle]
pub extern "C" fn sp_postgresql_escape_string(
    conn: *const SPPostgreSQLConnection,
    input: *const c_char,
) -> *mut c_char {
    if conn.is_null() || input.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let conn_ref = &(*conn).inner;
        let input_str = CStr::from_ptr(input).to_string_lossy().into_owned();
        let escaped = conn_ref.escape_string(&input_str);
        
        match CString::new(escaped) {
            Ok(c_str) => c_str.into_raw(),
            Err(_) => ptr::null_mut(),
        }
    }
}

// Database Operations

#[no_mangle]
pub extern "C" fn sp_postgresql_connection_list_databases(
    conn: *mut SPPostgreSQLConnection,
    count: *mut c_int,
) -> *mut *mut c_char {
    if conn.is_null() || count.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let conn_ref = &mut (*conn).inner;
        match conn_ref.list_databases() {
            Ok(databases) => {
                *count = databases.len() as c_int;
                
                let mut c_strings: Vec<*mut c_char> = databases
                    .into_iter()
                    .filter_map(|db| CString::new(db).ok())
                    .map(|c_str| c_str.into_raw())
                    .collect();
                
                c_strings.shrink_to_fit();
                let ptr = c_strings.as_mut_ptr();
                std::mem::forget(c_strings);
                ptr
            },
            Err(_) => {
                *count = 0;
                ptr::null_mut()
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn sp_postgresql_free_string_array(array: *mut *mut c_char, count: c_int) {
    if !array.is_null() && count > 0 {
        unsafe {
            let vec = Vec::from_raw_parts(array, count as usize, count as usize);
            for ptr in vec {
                if !ptr.is_null() {
                    let _ = CString::from_raw(ptr);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_connection_create_destroy() {
        let conn = sp_postgresql_connection_create();
        assert!(!conn.is_null());
        sp_postgresql_connection_destroy(conn);
    }
}

