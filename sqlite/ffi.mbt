///|
/// Raw C bindings to the vendored SQLite amalgamation. These are package
/// internals: the public surface is [`Sqlite`] in `sqlite.mbt`.

///|
/// Opaque handle for a `sqlite3*` connection. The pointer crosses the FFI as
/// an inert value — the GC neither traces nor frees it, so closing is the
/// caller's responsibility.
priv type Sqlite3

///|
/// Opaque handle for a `sqlite3_stmt*` prepared statement.
priv type Sqlite3Stmt

// Result codes and column type tags returned by SQLite.

///|
const SQLITE_OK : Int = 0

///|
const SQLITE_ROW : Int = 100

///|
const SQLITE_DONE : Int = 101

///|
const SQLITE_INTEGER : Int = 1

///|
const SQLITE_FLOAT : Int = 2

///|
const SQLITE_TEXT : Int = 3

///|
const SQLITE_BLOB : Int = 4

///|
const SQLITE_NULL : Int = 5

// `#borrow` marks arguments that C reads during the call but does not keep.

///|
#borrow(filename)
extern "C" fn sqlite_open(filename : Bytes) -> Sqlite3 = "sqlite_open"

///|
#borrow(db)
extern "C" fn sqlite_is_null(db : Sqlite3) -> Int = "sqlite_is_null"

///|
#borrow(db)
extern "C" fn sqlite_close(db : Sqlite3) -> Unit = "sqlite_close"

///|
#borrow(db, sql)
extern "C" fn sqlite_prepare(db : Sqlite3, sql : Bytes) -> Sqlite3Stmt = "sqlite_prepare"

///|
#borrow(stmt)
extern "C" fn sqlite_stmt_is_null(stmt : Sqlite3Stmt) -> Int = "sqlite_stmt_is_null"

///|
#borrow(stmt)
extern "C" fn sqlite_finalize(stmt : Sqlite3Stmt) -> Unit = "sqlite_finalize"

///|
#borrow(stmt)
extern "C" fn sqlite_bind_int(stmt : Sqlite3Stmt, idx : Int, value : Int) -> Int = "sqlite_bind_int"

///|
#borrow(stmt)
extern "C" fn sqlite_bind_double(stmt : Sqlite3Stmt, idx : Int, value : Double) -> Int = "sqlite_bind_double"

///|
#borrow(stmt, text)
extern "C" fn sqlite_bind_text(stmt : Sqlite3Stmt, idx : Int, text : Bytes) -> Int = "sqlite_bind_text"

///|
#borrow(stmt)
extern "C" fn sqlite_bind_null(stmt : Sqlite3Stmt, idx : Int) -> Int = "sqlite_bind_null"

///|
#borrow(stmt, blob)
extern "C" fn sqlite_bind_blob(stmt : Sqlite3Stmt, idx : Int, blob : Bytes) -> Int = "sqlite_bind_blob"

///|
#borrow(stmt)
extern "C" fn sqlite_step(stmt : Sqlite3Stmt) -> Int = "sqlite_step"

///|
#borrow(stmt)
extern "C" fn sqlite_column_int(stmt : Sqlite3Stmt, col : Int) -> Int = "sqlite_column_int"

///|
#borrow(stmt)
extern "C" fn sqlite_column_double(stmt : Sqlite3Stmt, col : Int) -> Double = "sqlite_column_double"

///|
#borrow(stmt)
extern "C" fn sqlite_column_text(stmt : Sqlite3Stmt, col : Int) -> Bytes = "sqlite_column_text"

///|
#borrow(stmt)
extern "C" fn sqlite_column_blob(stmt : Sqlite3Stmt, col : Int) -> Bytes = "sqlite_column_blob"

///|
#borrow(stmt)
extern "C" fn sqlite_column_type(stmt : Sqlite3Stmt, col : Int) -> Int = "sqlite_column_type"

///|
#borrow(stmt)
extern "C" fn sqlite_column_count(stmt : Sqlite3Stmt) -> Int = "sqlite_column_count"

///|
#borrow(stmt)
extern "C" fn sqlite_column_name(stmt : Sqlite3Stmt, col : Int) -> Bytes = "sqlite_column_name"

///|
#borrow(db)
extern "C" fn sqlite_errmsg(db : Sqlite3) -> Bytes = "sqlite_errmsg"

///|
#borrow(db)
extern "C" fn sqlite_changes(db : Sqlite3) -> Int = "sqlite_changes"

///|
#borrow(db)
extern "C" fn sqlite_last_insert_rowid(db : Sqlite3) -> Int64 = "sqlite_last_insert_rowid"
