//
//  sppostgresql_ffi.h
//  SPPostgreSQLFramework - C FFI API
//

#ifndef SPPOSTGRESQL_FFI_H
#define SPPOSTGRESQL_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

// Opaque types
typedef struct SPPostgreSQLConnection SPPostgreSQLConnection;
typedef struct SPPostgreSQLResult SPPostgreSQLResult;
typedef struct SPPostgreSQLStreamingResult SPPostgreSQLStreamingResult;

// ─── Connection Management ────────────────────────────────────────────────────

SPPostgreSQLConnection* sp_postgresql_connection_create(void);
void sp_postgresql_connection_destroy(SPPostgreSQLConnection* conn);

int sp_postgresql_connection_connect(
    SPPostgreSQLConnection* conn,
    const char* host,
    int port,
    const char* username,
    const char* password,
    const char* database,
    int use_ssl
);

void sp_postgresql_connection_disconnect(SPPostgreSQLConnection* conn);
int  sp_postgresql_connection_is_connected(const SPPostgreSQLConnection* conn);

// ─── Query Execution ──────────────────────────────────────────────────────────

SPPostgreSQLResult* sp_postgresql_connection_execute_query(
    SPPostgreSQLConnection* conn,
    const char* query
);

SPPostgreSQLStreamingResult* sp_postgresql_connection_execute_streaming_query(
    SPPostgreSQLConnection* conn,
    const char* query,
    int batch_size
);

// ─── Regular Result Management ────────────────────────────────────────────────

void               sp_postgresql_result_destroy(SPPostgreSQLResult* result);
int                sp_postgresql_result_num_rows(const SPPostgreSQLResult* result);
int                sp_postgresql_result_num_fields(const SPPostgreSQLResult* result);
unsigned long long sp_postgresql_result_affected_rows(const SPPostgreSQLResult* result);

char* sp_postgresql_result_field_name(
    const SPPostgreSQLResult* result,
    int field_index
);

unsigned int sp_postgresql_result_field_type_oid(
    const SPPostgreSQLResult* result,
    int field_index
);

char* sp_postgresql_result_get_value(
    const SPPostgreSQLResult* result,
    int row,
    int col
);

// ─── Streaming Result Management ─────────────────────────────────────────────

void      sp_postgresql_streaming_result_mark_disconnected(SPPostgreSQLStreamingResult* result);
void      sp_postgresql_streaming_result_destroy(SPPostgreSQLStreamingResult* result);
long long sp_postgresql_streaming_result_total_rows(const SPPostgreSQLStreamingResult* result);
int       sp_postgresql_streaming_result_num_fields(const SPPostgreSQLStreamingResult* result);
int       sp_postgresql_streaming_result_has_more(const SPPostgreSQLStreamingResult* result);

char* sp_postgresql_streaming_result_field_name(
    const SPPostgreSQLStreamingResult* result,
    int field_index
);

unsigned int sp_postgresql_streaming_result_field_type_oid(
    const SPPostgreSQLStreamingResult* result,
    int field_index
);

int sp_postgresql_streaming_result_next_batch(
    SPPostgreSQLStreamingResult* result,
    void* callback,
    void* user_data
);

char* sp_postgresql_streaming_result_get_batch_value(
    const SPPostgreSQLStreamingResult* result,
    int batch_relative_row,
    int col
);

int sp_postgresql_streaming_result_current_batch_size(const SPPostgreSQLStreamingResult* result);

// ─── Error Handling ───────────────────────────────────────────────────────────

char* sp_postgresql_connection_last_error(const SPPostgreSQLConnection* conn);

// ─── Utility ──────────────────────────────────────────────────────────────────

void  sp_postgresql_free_string(char* s);
char* sp_postgresql_escape_string(const SPPostgreSQLConnection* conn, const char* input);

// ─── Database Operations ──────────────────────────────────────────────────────

char** sp_postgresql_connection_list_databases(SPPostgreSQLConnection* conn, int* count);
void   sp_postgresql_free_string_array(char** array, int count);

#ifdef __cplusplus
}
#endif

#endif /* SPPOSTGRESQL_FFI_H */
