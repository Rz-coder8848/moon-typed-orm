#include "sqlite3.h"
#include <moonbit.h>
#include <stdlib.h>
#include <string.h>

// MoonBit `Bytes` is length-prefixed; SQLite wants a NUL-terminated char*.
// Copy into a fresh buffer and add the terminator.
static char* bytes_to_cstring(moonbit_bytes_t bytes) {
  int32_t len = Moonbit_array_length(bytes);
  char* str = (char*)malloc((size_t)len + 1);
  memcpy(str, bytes, (size_t)len);
  str[len] = '\0';
  return str;
}

sqlite3* sqlite_open(moonbit_bytes_t filename) {
  char* fname = bytes_to_cstring(filename);
  sqlite3* db = NULL;
  int rc = sqlite3_open(fname, &db);
  free(fname);
  if (rc != SQLITE_OK) {
    if (db) sqlite3_close(db);
    return NULL;
  }
  return db;
}

int32_t sqlite_is_null(sqlite3* db) {
  return db == NULL ? 1 : 0;
}

int32_t sqlite_stmt_is_null(sqlite3_stmt* stmt) {
  return stmt == NULL ? 1 : 0;
}

void sqlite_close(sqlite3* db) {
  sqlite3_close(db);
}

sqlite3_stmt* sqlite_prepare(sqlite3* db, moonbit_bytes_t sql) {
  char* sql_str = bytes_to_cstring(sql);
  sqlite3_stmt* stmt = NULL;
  int rc = sqlite3_prepare_v2(db, sql_str, -1, &stmt, NULL);
  free(sql_str);
  if (rc != SQLITE_OK) return NULL;
  return stmt;
}

void sqlite_finalize(sqlite3_stmt* stmt) {
  sqlite3_finalize(stmt);
}

int32_t sqlite_bind_int(sqlite3_stmt* stmt, int32_t idx, int32_t value) {
  return sqlite3_bind_int(stmt, idx, value);
}

int32_t sqlite_bind_double(sqlite3_stmt* stmt, int32_t idx, double value) {
  return sqlite3_bind_double(stmt, idx, value);
}

int32_t sqlite_bind_text(sqlite3_stmt* stmt, int32_t idx, moonbit_bytes_t text) {
  char* s = bytes_to_cstring(text);
  int rc = sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT);
  free(s);
  return rc;
}

int32_t sqlite_bind_null(sqlite3_stmt* stmt, int32_t idx) {
  return sqlite3_bind_null(stmt, idx);
}

int32_t sqlite_bind_blob(sqlite3_stmt* stmt, int32_t idx, moonbit_bytes_t blob) {
  int32_t len = Moonbit_array_length(blob);
  return sqlite3_bind_blob(stmt, idx, blob, len, SQLITE_TRANSIENT);
}

int32_t sqlite_step(sqlite3_stmt* stmt) {
  return sqlite3_step(stmt);
}

int32_t sqlite_column_int(sqlite3_stmt* stmt, int32_t col) {
  return sqlite3_column_int(stmt, col);
}

double sqlite_column_double(sqlite3_stmt* stmt, int32_t col) {
  return sqlite3_column_double(stmt, col);
}

moonbit_bytes_t sqlite_column_text(sqlite3_stmt* stmt, int32_t col) {
  const unsigned char* text = sqlite3_column_text(stmt, col);
  int len = sqlite3_column_bytes(stmt, col);
  if (text == NULL || len <= 0) return moonbit_make_bytes(0, 0);
  moonbit_bytes_t result = moonbit_make_bytes(len, 0);
  memcpy(result, text, (size_t)len);
  return result;
}

moonbit_bytes_t sqlite_column_blob(sqlite3_stmt* stmt, int32_t col) {
  const void* blob = sqlite3_column_blob(stmt, col);
  int len = sqlite3_column_bytes(stmt, col);
  if (blob == NULL || len <= 0) return moonbit_make_bytes(0, 0);
  moonbit_bytes_t result = moonbit_make_bytes(len, 0);
  memcpy(result, blob, (size_t)len);
  return result;
}

int32_t sqlite_column_type(sqlite3_stmt* stmt, int32_t col) {
  return sqlite3_column_type(stmt, col);
}

int32_t sqlite_column_count(sqlite3_stmt* stmt) {
  return sqlite3_column_count(stmt);
}

moonbit_bytes_t sqlite_column_name(sqlite3_stmt* stmt, int32_t col) {
  const char* name = sqlite3_column_name(stmt, col);
  if (!name) return moonbit_make_bytes(0, 0);
  int32_t len = (int32_t)strlen(name);
  moonbit_bytes_t result = moonbit_make_bytes(len, 0);
  memcpy(result, name, (size_t)len);
  return result;
}

moonbit_bytes_t sqlite_errmsg(sqlite3* db) {
  const char* msg = sqlite3_errmsg(db);
  if (!msg) return moonbit_make_bytes(0, 0);
  int32_t len = (int32_t)strlen(msg);
  moonbit_bytes_t result = moonbit_make_bytes(len, 0);
  memcpy(result, msg, (size_t)len);
  return result;
}

int32_t sqlite_changes(sqlite3* db) {
  return sqlite3_changes(db);
}

int64_t sqlite_last_insert_rowid(sqlite3* db) {
  return sqlite3_last_insert_rowid(db);
}
