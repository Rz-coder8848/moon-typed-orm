///|
/// SQLite backend for Moon-Typed-ORM.
///
/// Renders a builder with `build()`, prepares the SQL with `sqlite3_prepare_v2`,
/// binds each [`Value`] positionally through the matching `sqlite3_bind_*`, then
/// steps the statement. Values are never spliced into the SQL text.
///
/// Links a vendored copy of the SQLite amalgamation (`sqlite3.c`), so the only
/// external requirement is the `native` target plus a C toolchain. Not available
/// on wasm-gc.

///|
pub struct Sqlite {
  priv handle : Sqlite3
}

///|
/// Open a database file, or `":memory:"` for a private in-memory database.
pub fn Sqlite::open(path : String) -> Sqlite raise @moonorm.OrmError {
  let handle = sqlite_open(encode(path))
  if sqlite_is_null(handle) == 1 {
    raise @moonorm.OrmError::backend("cannot open database")
  }
  { handle, }
}

///|
/// Close the underlying handle. Required to release the native resources.
pub fn Sqlite::close(self : Sqlite) -> Unit {
  sqlite_close(self.handle)
}

///|
/// Run a raw statement with no bound parameters (DDL, pragmas, etc.).
pub fn Sqlite::exec(
  self : Sqlite,
  sql : String,
) -> Unit raise @moonorm.OrmError {
  let _ = self.exec_changes(sql, [])
}

///|
/// Prepare `sql` and bind `params` positionally, returning a ready statement.
fn Sqlite::prepare_bound(
  self : Sqlite,
  sql : String,
  params : Array[@moonorm.Value],
) -> Sqlite3Stmt raise @moonorm.OrmError {
  let stmt = sqlite_prepare(self.handle, encode(sql))
  if sqlite_stmt_is_null(stmt) == 1 {
    raise @moonorm.OrmError::backend(decode(sqlite_errmsg(self.handle)))
  }
  for i, value in params {
    let rc = bind_value(stmt, i + 1, value)
    if rc != SQLITE_OK {
      sqlite_finalize(stmt)
      raise @moonorm.OrmError::backend(decode(sqlite_errmsg(self.handle)))
    }
  }
  stmt
}

///|
/// Step a prepared statement and return `(rows_affected, last_insert_rowid)`.
fn Sqlite::exec_changes(
  self : Sqlite,
  sql : String,
  params : Array[@moonorm.Value],
) -> (Int, Int64) raise @moonorm.OrmError {
  let stmt = self.prepare_bound(sql, params)
  let rc = sqlite_step(stmt)
  sqlite_finalize(stmt)
  if rc != SQLITE_DONE && rc != SQLITE_ROW {
    raise @moonorm.OrmError::backend(decode(sqlite_errmsg(self.handle)))
  }
  (sqlite_changes(self.handle), sqlite_last_insert_rowid(self.handle))
}

///|
pub impl @moonorm.Connection for Sqlite with fn select(
  self : Sqlite,
  query : @moonorm.Select,
) -> Array[@moonorm.Row] raise @moonorm.OrmError {
  let built = try! query.build()
  let stmt = self.prepare_bound(built.to_sql(), built.to_params())
  let rows = collect_rows(stmt)
  sqlite_finalize(stmt)
  rows
}

///|
pub impl @moonorm.Connection for Sqlite with fn insert(
  self : Sqlite,
  query : @moonorm.Insert,
) -> @moonorm.ExecResult raise @moonorm.OrmError {
  let built = try! query.build()
  let (changes, rowid) = self.exec_changes(built.to_sql(), built.to_params())
  @moonorm.ExecResult::new(changes, last_insert_id=rowid.to_int())
}

///|
pub impl @moonorm.Connection for Sqlite with fn update(
  self : Sqlite,
  query : @moonorm.Update,
) -> @moonorm.ExecResult raise @moonorm.OrmError {
  let built = try! query.build()
  let (changes, _) = self.exec_changes(built.to_sql(), built.to_params())
  @moonorm.ExecResult::new(changes)
}

///|
pub impl @moonorm.Connection for Sqlite with fn delete(
  self : Sqlite,
  query : @moonorm.Delete,
) -> @moonorm.ExecResult raise @moonorm.OrmError {
  let built = try! query.build()
  let (changes, _) = self.exec_changes(built.to_sql(), built.to_params())
  @moonorm.ExecResult::new(changes)
}

///|
/// Make the backend methods callable directly as `db.select(...)`, `db.insert(...)`,
/// and so on.
pub extend Sqlite with @moonorm.Connection::{select, insert, update, delete}

///|
/// `Sqlite` supports explicit transactions over the same connection.
pub impl @moonorm.Transactional for Sqlite with fn begin(self : Sqlite) -> Unit raise @moonorm.OrmError {
  self.exec("BEGIN")
}

///|
pub impl @moonorm.Transactional for Sqlite with fn commit(self : Sqlite) -> Unit raise @moonorm.OrmError {
  self.exec("COMMIT")
}

///|
pub impl @moonorm.Transactional for Sqlite with fn rollback(self : Sqlite) -> Unit raise @moonorm.OrmError {
  self.exec("ROLLBACK")
}

///|
/// Make the transaction methods callable directly as `db.begin()`, `db.commit()`,
/// and `db.rollback()`.
pub extend Sqlite with @moonorm.Transactional::{begin, commit, rollback}

///|
/// Translate a [`Value`] into the matching `sqlite3_bind_*` call. Returns the
/// SQLite result code (0 = OK).
fn bind_value(stmt : Sqlite3Stmt, idx : Int, value : @moonorm.Value) -> Int {
  match value {
    @moonorm.Value::Null => sqlite_bind_null(stmt, idx)
    @moonorm.Value::Bool(b) => sqlite_bind_int(stmt, idx, if b { 1 } else { 0 })
    @moonorm.Value::Int(n) => sqlite_bind_int(stmt, idx, n)
    @moonorm.Value::Float(f) => sqlite_bind_double(stmt, idx, f)
    @moonorm.Value::Text(s) => sqlite_bind_text(stmt, idx, encode(s))
    @moonorm.Value::Blob(b) => sqlite_bind_blob(stmt, idx, b)
  }
}

///|
/// Step through all rows of `stmt` and collect them as [`Row`]s.
fn collect_rows(stmt : Sqlite3Stmt) -> Array[@moonorm.Row] {
  let ncols = sqlite_column_count(stmt)
  let columns : Array[String] = []
  for i in 0..<ncols {
    columns.push(decode(sqlite_column_name(stmt, i)))
  }
  let rows : Array[@moonorm.Row] = []
  let mut rc = sqlite_step(stmt)
  while rc == SQLITE_ROW {
    let values : Array[@moonorm.Value] = []
    for i in 0..<ncols {
      values.push(read_value(stmt, i))
    }
    rows.push(@moonorm.Row::new(columns, values))
    rc = sqlite_step(stmt)
  }
  rows
}

///|
/// Read the value of column `col`, typed by SQLite's declared column type.
fn read_value(stmt : Sqlite3Stmt, col : Int) -> @moonorm.Value {
  match sqlite_column_type(stmt, col) {
    SQLITE_NULL => @moonorm.Value::null()
    SQLITE_INTEGER => @moonorm.Value::int(sqlite_column_int(stmt, col))
    SQLITE_FLOAT => @moonorm.Value::float(sqlite_column_double(stmt, col))
    SQLITE_TEXT => @moonorm.Value::text(decode(sqlite_column_text(stmt, col)))
    SQLITE_BLOB => @moonorm.Value::blob(sqlite_column_blob(stmt, col))
    _ => @moonorm.Value::null()
  }
}

///|
fn encode(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
fn decode(b : Bytes) -> String {
  @utf8.decode_lossy(b)
}
