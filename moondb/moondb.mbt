///|
/// Moondb backend: runs the typed builders against any [`@db.Driver`].
///
/// [`Moondb`] bridges the root package's structured query DSL onto the
/// [moondb](https://mooncakes.io/packages/moonbitstack/moondb) driver seam — the
/// shared contract the MoonBit database stack (moonorm and friends) is built on.
/// It renders a builder with `build()`, translates the bound [`@moonorm.Value`]s
/// into `@db.Value`, and delegates to the wrapped driver; a `@db.DbError`
/// is re-raised as [`@moonorm.OrmError::Backend`].
///
/// Because it sits on the standard seam, the same DSL drives SQLite, Postgres,
/// MySQL, or the dependency-free [`@db.MockDriver`] without a second backend.
pub struct Moondb {
  driver : &@db.Driver
}

///|
/// Wrap a connected driver. Pass any [`@db.Driver`] value directly —
/// `Moondb::new(@db.MockDriver::new())` borrows it into a trait object.
pub fn Moondb::new(driver : &@db.Driver) -> Moondb {
  { driver, }
}

///|
/// Close the wrapped driver. Best-effort and idempotent, like the underlying
/// [`@db.Driver::close`].
pub fn Moondb::close(self : Moondb) -> Unit {
  self.driver.close()
}

///|
pub impl @moonorm.Connection for Moondb with fn select(
  self : Moondb,
  query : @moonorm.Select,
) -> Array[@moonorm.Row] raise @moonorm.OrmError {
  let built = try! query.build()
  let rows = self.driver.query(
    built.to_sql(),
    built.to_params().map(fn(v) { to_moondb_value(v) }),
  ) catch {
    err => raise @moonorm.OrmError::backend(err.to_string())
  }
  rows.map(fn(r) { from_moondb_row(r) })
}

///|
pub impl @moonorm.Connection for Moondb with fn insert(
  self : Moondb,
  query : @moonorm.Insert,
) -> @moonorm.ExecResult raise @moonorm.OrmError {
  let built = try! query.build()
  let res = self.driver.execute(
    built.to_sql(),
    built.to_params().map(fn(v) { to_moondb_value(v) }),
  ) catch {
    err => raise @moonorm.OrmError::backend(err.to_string())
  }
  @moonorm.ExecResult::new(
    res.rows_affected.to_int(),
    last_insert_id=res.last_insert_id.to_int(),
  )
}

///|
pub impl @moonorm.Connection for Moondb with fn update(
  self : Moondb,
  query : @moonorm.Update,
) -> @moonorm.ExecResult raise @moonorm.OrmError {
  let built = try! query.build()
  let res = self.driver.execute(
    built.to_sql(),
    built.to_params().map(fn(v) { to_moondb_value(v) }),
  ) catch {
    err => raise @moonorm.OrmError::backend(err.to_string())
  }
  @moonorm.ExecResult::new(res.rows_affected.to_int())
}

///|
pub impl @moonorm.Connection for Moondb with fn delete(
  self : Moondb,
  query : @moonorm.Delete,
) -> @moonorm.ExecResult raise @moonorm.OrmError {
  let built = try! query.build()
  let res = self.driver.execute(
    built.to_sql(),
    built.to_params().map(fn(v) { to_moondb_value(v) }),
  ) catch {
    err => raise @moonorm.OrmError::backend(err.to_string())
  }
  @moonorm.ExecResult::new(res.rows_affected.to_int())
}

///|
/// Make the backend methods callable directly as `db.select(...)`, `db.insert(...)`,
/// and so on.
pub extend Moondb with @moonorm.Connection::{select, insert, update, delete}

///|
/// `Moondb` delegates transactions straight through to the wrapped driver.
pub impl @moonorm.Transactional for Moondb with fn begin(self : Moondb) -> Unit raise @moonorm.OrmError {
  self.driver.begin() catch {
    err => raise @moonorm.OrmError::backend(err.to_string())
  }
}

///|
pub impl @moonorm.Transactional for Moondb with fn commit(self : Moondb) -> Unit raise @moonorm.OrmError {
  self.driver.commit() catch {
    err => raise @moonorm.OrmError::backend(err.to_string())
  }
}

///|
pub impl @moonorm.Transactional for Moondb with fn rollback(self : Moondb) -> Unit raise @moonorm.OrmError {
  self.driver.rollback() catch {
    err => raise @moonorm.OrmError::backend(err.to_string())
  }
}

///|
/// Make the transaction methods callable directly as `db.begin()`, `db.commit()`,
/// and `db.rollback()`.
pub extend Moondb with @moonorm.Transactional::{begin, commit, rollback}

///|
/// Translate a moon-typed-orm [`@moonorm.Value`] into the `@db` equivalent for
/// binding.
fn to_moondb_value(value : @moonorm.Value) -> @db.Value {
  match value {
    @moonorm.Value::Null => @db.Value::Null
    @moonorm.Value::Bool(b) => @db.Value::Bool(b)
    @moonorm.Value::Int(n) => @db.Value::Int(n)
    @moonorm.Value::Float(f) => @db.Value::Double(f)
    @moonorm.Value::Text(s) => @db.Value::Text(s)
    @moonorm.Value::Blob(b) => @db.Value::Blob(b)
  }
}

///|
/// Translate a `@db.Value` back into a moon-typed-orm [`@moonorm.Value`]. The
/// driver's extra `Int64` case narrows to `Int`, matching how the in-memory and
/// SQLite backends already read integers.
fn from_moondb_value(value : @db.Value) -> @moonorm.Value {
  match value {
    @db.Value::Null => @moonorm.Value::null()
    @db.Value::Bool(b) => @moonorm.Value::bool(b)
    @db.Value::Int(n) => @moonorm.Value::int(n)
    @db.Value::Int64(n) => @moonorm.Value::int(n.to_int())
    @db.Value::Double(f) => @moonorm.Value::float(f)
    @db.Value::Text(s) => @moonorm.Value::text(s)
    @db.Value::Blob(b) => @moonorm.Value::blob(b)
  }
}

///|
/// Translate a `@db.Row` into the root package's [`@moonorm.Row`].
fn from_moondb_row(row : @db.Row) -> @moonorm.Row {
  @moonorm.Row::new(row.columns, row.values.map(fn(v) { from_moondb_value(v) }))
}
