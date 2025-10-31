//
//  sppostgresql_ffi.h
//  SPPostgreSQLFramework - C API
//
//  Created by Sequel Ace on 2024.
//  Copyright (c) 2024 Sequel Ace. All rights reserved.
//

#ifndef SPPOSTGRESQL_FFI_H
#define SPPOSTGRESQL_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

// Opaque types
typedef struct SPPostgreSQLConnection SPPostgreSQLConnection;
typedef struct SPPostgreSQLResult SPPostgreSQLResult;

// Connection Management

/**
 * Create a new PostgreSQL connection
 * @return Pointer to connection object or NULL on failure
 */
SPPostgreSQLConnection* sp_postgresql_connection_create(void);

/**
 * Destroy a PostgreSQL connection and free resources
 * @param conn Connection to destroy
 */
void sp_postgresql_connection_destroy(SPPostgreSQLConnection* conn);

/**
 * Connect to PostgreSQL server
 * @param conn Connection object
 * @param host Hostname or IP address
 * @param port Port number
 * @param username Username for authentication
 * @param password Password for authentication
 * @param database Database name to connect to
 * @param use_ssl Use SSL/TLS (1 = yes, 0 = no)
 * @return 1 on success, 0 on failure
 */
int sp_postgresql_connection_connect(
    SPPostgreSQLConnection* conn,
    const char* host,
    int port,
    const char* username,
    const char* password,
    const char* database,
    int use_ssl
);

/**
 * Disconnect from PostgreSQL server
 * @param conn Connection object
 */
void sp_postgresql_connection_disconnect(SPPostgreSQLConnection* conn);

/**
 * Check if connected to server
 * @param conn Connection object
 * @return 1 if connected, 0 if not
 */
int sp_postgresql_connection_is_connected(const SPPostgreSQLConnection* conn);

// Query Execution

/**
 * Execute a SQL query
 * @param conn Connection object
 * @param query SQL query string
 * @return Pointer to result object or NULL on failure
 */
SPPostgreSQLResult* sp_postgresql_connection_execute_query(
    SPPostgreSQLConnection* conn,
    const char* query
);

// Result Management

/**
 * Destroy a result set and free resources
 * @param result Result object to destroy
 */
void sp_postgresql_result_destroy(SPPostgreSQLResult* result);

/**
 * Get number of rows in result set
 * @param result Result object
 * @return Number of rows
 */
int sp_postgresql_result_num_rows(const SPPostgreSQLResult* result);

/**
 * Get number of fields/columns in result set
 * @param result Result object
 * @return Number of fields
 */
int sp_postgresql_result_num_fields(const SPPostgreSQLResult* result);

/**
 * Get field name by index
 * @param result Result object
 * @param field_index Field index (0-based)
 * @return Field name (caller must free with sp_postgresql_free_string)
 */
char* sp_postgresql_result_field_name(
    const SPPostgreSQLResult* result,
    int field_index
);

/**
 * Get value at specific row and column
 * @param result Result object
 * @param row Row index (0-based)
 * @param col Column index (0-based)
 * @return Value as string (caller must free with sp_postgresql_free_string)
 */
char* sp_postgresql_result_get_value(
    const SPPostgreSQLResult* result,
    int row,
    int col
);

// Error Handling

/**
 * Get last error message
 * @param conn Connection object
 * @return Error message (caller must free with sp_postgresql_free_string)
 */
char* sp_postgresql_connection_last_error(const SPPostgreSQLConnection* conn);

// Utility Functions

/**
 * Free a string allocated by Rust
 * @param s String to free
 */
void sp_postgresql_free_string(char* s);

/**
 * Escape a string for safe use in SQL queries
 * @param conn Connection object
 * @param input String to escape
 * @return Escaped string (caller must free with sp_postgresql_free_string)
 */
char* sp_postgresql_escape_string(
    const SPPostgreSQLConnection* conn,
    const char* input
);

// Database Operations

/**
 * List all databases on the server
 * @param conn Connection object
 * @param count Output parameter for number of databases
 * @return Array of database names (caller must free with sp_postgresql_free_string_array)
 */
char** sp_postgresql_connection_list_databases(
    SPPostgreSQLConnection* conn,
    int* count
);

/**
 * Free an array of strings
 * @param array Array to free
 * @param count Number of strings in array
 */
void sp_postgresql_free_string_array(char** array, int count);

#ifdef __cplusplus
}
#endif

#endif /* SPPOSTGRESQL_FFI_H */

