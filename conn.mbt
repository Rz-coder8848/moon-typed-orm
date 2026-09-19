///|
/// A single result row: ordered column names and their values.
pub struct Row {
  columns : Array[String]
  values : Array[Value]
} derive(Eq, @debug.Debug)

///|
pub fn Row::new(columns : Array[String], values : Array[Value]) -> Row {
  { columns, values, }
}

///|
pub fn Row::get(self : Row, column : String) -> Value? {
  for i, name in self.columns {
    if name == column {
      return self.values.get(i)
    }
  }
  None
}

///|
pub fn Row::get_at(self : Row, index : Int) -> Value? {
  self.values.get(index)
}

///|
/// Outcome of a statement that mutates data.
pub struct ExecResult {
  rows_affected : Int
  last_insert_id : Int?
} derive(Eq, @debug.Debug)

///|
pub fn ExecResult::new(
  rows_affected : Int,
  last_insert_id? : Int,
) -> ExecResult {
  { rows_affected, last_insert_id, }
}

///|
/// A database backend. Builders are handed over as structured queries: a SQL
/// driver renders them with [`Select::build`] and binds parameters, while the
/// in-memory backend evaluates them directly. This trait is the replaceable
/// boundary — swap [`Memory`] for a SQLite or Postgres driver without touching
/// call sites.
pub(open) trait Connection {
  fn select(Self, Select) -> Array[Row] raise OrmError
  fn insert(Self, Insert) -> ExecResult raise OrmError
  fn update(Self, Update) -> ExecResult raise OrmError
  fn delete(Self, Delete) -> ExecResult raise OrmError
}

///|
/// A connection that can run explicit transactions. Backends that don't support
/// multi-statement transactions (for example a single-statement in-memory store)
/// simply don't implement this trait — capabilities are opt-in, and
/// [`Connection`] stays the narrow boundary every backend shares.
pub(open) trait Transactional {
  fn begin(Self) -> Unit raise OrmError
  fn commit(Self) -> Unit raise OrmError
  fn rollback(Self) -> Unit raise OrmError
}
