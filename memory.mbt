///|
/// In-memory backend: a dependency-free table store for tests, demos and CI.
///
/// Implements [`Connection`] by evaluating the structured builders directly, so
/// query code runs unchanged against this backend or a future SQL driver.
/// Supports a single inner join (nested-loop) in addition to single-table
/// queries; `raw` SQL conditions are rejected with [`OrmError::Backend`].
pub struct Memory {
  tables : @hashmap.HashMap[String, MemoryTable]
}

///|
struct MemoryTable {
  columns : Array[String]
  rows : Array[Array[Value]]
}

///|
pub fn Memory::new() -> Memory {
  { tables: @hashmap.HashMap([]), }
}

///|
/// Define a table before inserting into it.
pub fn Memory::create_table(
  self : Memory,
  name : String,
  columns : Array[String],
) -> Unit raise OrmError {
  if self.tables.contains(name) {
    raise OrmError::Backend("table already exists: \{name}")
  }
  self.tables.set(name, { columns, rows: [], })
}

///|
pub impl Connection for Memory with fn select(self, query) {
  mem_select(self, query, None)
}

///|
pub impl Connection for Memory with fn insert(self, query) {
  mem_insert(self, query)
}

///|
pub impl Connection for Memory with fn update(self, query) {
  mem_update(self, query)
}

///|
pub impl Connection for Memory with fn delete(self, query) {
  mem_delete(self, query)
}

///|
/// Make the backend methods callable directly as `db.select(...)`, `db.insert(...)`,
/// and so on.
pub extend Memory with Connection::{select, insert, update, delete}

///|
fn get_table(
  tables : @hashmap.HashMap[String, MemoryTable],
  name : String,
) -> MemoryTable raise OrmError {
  match tables.get(name) {
    None => raise OrmError::Backend("table not found: \{name}")
    Some(t) => t
  }
}

///|
/// Join two tables by `join.on`, honoring `join.kind`. Column names are
/// qualified with their table so columns from either side stay addressable.
/// `INNER` keeps only matching pairs; `LEFT` / `RIGHT` keep unmatched rows from
/// one side (the other side's columns become null); `FULL` keeps both.
fn join_rows(
  mem : Memory,
  left_table : String,
  join : Join,
) -> (Array[String], Array[Array[Value]]) raise OrmError {
  let left = get_table(mem.tables, left_table)
  let right = get_table(mem.tables, join.table)
  let columns = left.columns.map(fn(c) { left_table + "." + c }) +
    right.columns.map(fn(c) { join.table + "." + c })

  // Every matching left/right pair, plus a per-row flag that it found a match.
  let matched : Array[Array[Value]] = []
  let left_matched : Array[Bool] = left.rows.map(fn(_) { false })
  let right_matched : Array[Bool] = right.rows.map(fn(_) { false })
  for i, lr in left.rows {
    for j, rr in right.rows {
      let combined = lr + rr
      if matches(mem, Some(join.on), [left_table, join.table], columns, combined, None) {
        matched.push(combined)
        left_matched[i] = true
        right_matched[j] = true
      }
    }
  }

  let rows = match join.kind {
    JoinKind::Inner => matched
    JoinKind::Left => {
      for i, lr in left.rows {
        if !left_matched[i] {
          matched.push(lr + null_row(right.columns.length()))
        }
      }
      matched
    }
    JoinKind::Right => {
      for j, rr in right.rows {
        if !right_matched[j] {
          matched.push(null_row(left.columns.length()) + rr)
        }
      }
      matched
    }
    JoinKind::Full => {
      for i, lr in left.rows {
        if !left_matched[i] {
          matched.push(lr + null_row(right.columns.length()))
        }
      }
      for j, rr in right.rows {
        if !right_matched[j] {
          matched.push(null_row(left.columns.length()) + rr)
        }
      }
      matched
    }
  }
  (columns, rows)
}

///|
/// An array of `n` null values, used to pad the missing side of an outer join.
fn null_row(n : Int) -> Array[Value] {
  let out : Array[Value] = []
  for _ in 0..<n {
    out.push(Value::Null)
  }
  out
}

///|
fn mem_select(
  mem : Memory,
  query : Select,
  outer : (Array[String], Array[Value])?,
) -> Array[Row] raise OrmError {
  validate_supported(query.condition)
  validate_supported(query.having)
  match query.join {
    Some(j) => validate_supported(Some(j.on))
    None => ()
  }
  let tables = match query.join {
    None => [query.table]
    Some(j) => [query.table, j.table]
  }
  let (columns, rows) = match query.join {
    None => {
      let table = get_table(mem.tables, query.table)
      (table.columns, table.rows)
    }
    Some(j) => join_rows(mem, query.table, j)
  }
  let filtered : Array[Array[Value]] = []
  for row in rows {
    if matches(mem, query.condition, tables, columns, row, outer) {
      filtered.push(row)
    }
  }
  if query.group_by.is_empty() {
    match query.aggregate {
      Some(agg) => {
        let value = aggregate_value(agg, columns, filtered)
        [Row::new([aggregate_label(agg)], [value])]
      }
      None => {
        if !query.orders.is_empty() {
          filtered.sort_by(fn(a, b) { row_compare(a, b, columns, query.orders) })
        }
        let limited = apply_limit_offset(filtered, query.limit, query.offset)
        project(limited, columns, query.columns)
      }
    }
  } else {
    mem_select_grouped(mem, tables, columns, query, filtered)
  }
}

///|
fn mem_insert(mem : Memory, query : Insert) -> ExecResult raise OrmError {
  let table = get_table(mem.tables, query.table)
  let row = table.columns.map(fn(col) {
    match find_assignment(query.assignments, col) {
      None => Value::Null
      Some(v) => v
    }
  })
  mem.tables.set(query.table, { ..table, rows: table.rows + [row], })
  ExecResult::new(1)
}

///|
fn mem_update(mem : Memory, query : Update) -> ExecResult raise OrmError {
  validate_supported(query.condition)
  let table = get_table(mem.tables, query.table)
  let mut affected = 0
  let updated : Array[Array[Value]] = []
  for row in table.rows {
    if matches(mem, query.condition, [query.table], table.columns, row, None) {
      affected = affected + 1
      updated.push(apply_assignments(row, table.columns, query.assignments))
    } else {
      updated.push(row)
    }
  }
  mem.tables.set(query.table, { ..table, rows: updated, })
  ExecResult::new(affected)
}

///|
fn mem_delete(mem : Memory, query : Delete) -> ExecResult raise OrmError {
  validate_supported(query.condition)
  let table = get_table(mem.tables, query.table)
  let kept : Array[Array[Value]] = []
  for row in table.rows {
    if !matches(mem, query.condition, [query.table], table.columns, row, None) {
      kept.push(row)
    }
  }
  let affected = table.rows.length() - kept.length()
  mem.tables.set(query.table, { ..table, rows: kept, })
  ExecResult::new(affected)
}

///|
fn matches(
  mem : Memory,
  condition : Condition?,
  tables : Array[String],
  columns : Array[String],
  row : Array[Value],
  outer : (Array[String], Array[Value])?,
) -> Bool raise OrmError {
  match condition {
    None => true
    Some(c) => eval_condition(mem, c, tables, columns, row, outer)
  }
}

///|
fn eval_condition(
  mem : Memory,
  cond : Condition,
  tables : Array[String],
  columns : Array[String],
  row : Array[Value],
  outer : (Array[String], Array[Value])?,
) -> Bool raise OrmError {
  match cond {
    Condition::Compare(col, op, value) =>
      match column_value_scoped(col, tables, columns, row, outer) {
        None => false
        Some(actual) => compare_values(actual, op, value)
      }
    Condition::CompareCol(left, op, right) =>
      match (
        column_value_scoped(left, tables, columns, row, outer),
        column_value_scoped(right, tables, columns, row, outer),
      ) {
        (Some(a), Some(b)) => compare_values(a, op, b)
        _ => false
      }
    Condition::CompareSub(col, op, sub) => {
      let sub_rows = mem_select(mem, sub, Some((columns, row)))
      match sub_rows.get(0) {
        None => false
        Some(r) =>
          match (column_value_scoped(col, tables, columns, row, outer), r.get_at(0)) {
            (Some(actual), Some(scalar)) => compare_values(actual, op, scalar)
            _ => false
          }
      }
    }
    Condition::In(col, values) =>
      match column_value_scoped(col, tables, columns, row, outer) {
        None => false
        Some(actual) => values.contains(actual)
      }
    Condition::InSelect(col, sub) => {
      let sub_rows = mem_select(mem, sub, Some((columns, row)))
      let vals = sub_rows.map(fn(r) {
        match r.get_at(0) {
          None => Value::Null
          Some(v) => v
        }
      })
      match column_value_scoped(col, tables, columns, row, outer) {
        None => false
        Some(actual) => vals.contains(actual)
      }
    }
    Condition::IsNull(col) =>
      match column_value_scoped(col, tables, columns, row, outer) {
        None => true
        Some(Value::Null) => true
        Some(_) => false
      }
    Condition::IsNotNull(col) =>
      match column_value_scoped(col, tables, columns, row, outer) {
        None => false
        Some(Value::Null) => false
        Some(_) => true
      }
    Condition::Exists(sub) => !mem_select(mem, sub, Some((columns, row))).is_empty()
    Condition::And(a, b) =>
      eval_condition(mem, a, tables, columns, row, outer) &&
      eval_condition(mem, b, tables, columns, row, outer)
    Condition::Or(a, b) =>
      eval_condition(mem, a, tables, columns, row, outer) ||
      eval_condition(mem, b, tables, columns, row, outer)
    Condition::Not(a) => !eval_condition(mem, a, tables, columns, row, outer)
    Condition::Raw(_) => false
  }
}

///|
fn validate_supported(condition : Condition?) -> Unit raise OrmError {
  match condition {
    None => ()
    Some(cond) =>
      match cond {
        Condition::Raw(_) =>
          raise OrmError::Backend(
            "raw SQL conditions are not supported by the in-memory backend",
          )
        Condition::And(a, b) => {
          validate_supported(Some(a))
          validate_supported(Some(b))
        }
        Condition::Or(a, b) => {
          validate_supported(Some(a))
          validate_supported(Some(b))
        }
        Condition::Not(a) => validate_supported(Some(a))
        _ => ()
      }
  }
}

///|
fn column_value(
  col : ColumnRef,
  columns : Array[String],
  row : Array[Value],
) -> Value? {
  let qualified = col.table + "." + col.name
  for i, name in columns {
    if name == qualified {
      return row.get(i)
    }
  }
  for i, name in columns {
    if name == col.name {
      return row.get(i)
    }
  }
  None
}

///|
/// Resolve `col` within a single table scope. Only columns whose table is one of
/// `tables` are matched unqualified — this is what keeps an inner column from
/// shadowing an outer column of the same name in a correlated subquery.
fn resolve_in_scope(
  col : ColumnRef,
  tables : Array[String],
  columns : Array[String],
  row : Array[Value],
) -> Value? {
  let qualified = col.table + "." + col.name
  for i, name in columns {
    if name == qualified {
      return row.get(i)
    }
  }
  if tables.contains(col.table) {
    for i, name in columns {
      if name == col.name {
        return row.get(i)
      }
    }
  }
  None
}

///|
/// Resolve `col` against the current scope first, then fall back to the outer
/// scope — the row a correlated subquery is being evaluated against.
fn column_value_scoped(
  col : ColumnRef,
  tables : Array[String],
  columns : Array[String],
  row : Array[Value],
  outer : (Array[String], Array[Value])?,
) -> Value? {
  match resolve_in_scope(col, tables, columns, row) {
    None =>
      match outer {
        None => None
        Some((ocols, orow)) => column_value(col, ocols, orow)
      }
    Some(v) => Some(v)
  }
}

///|
fn compare_values(a : Value, op : CompareOp, b : Value) -> Bool {
  match op {
    CompareOp::Eq => a == b
    CompareOp::Ne => a != b
    CompareOp::Like =>
      match (a, b) {
        (Value::Text(s), Value::Text(p)) => like_match(s, p)
        _ => false
      }
    _ =>
      match try_compare(a, b) {
        None => false
        Some(c) =>
          match op {
            CompareOp::Gt => c > 0
            CompareOp::Gte => c >= 0
            CompareOp::Lt => c < 0
            CompareOp::Lte => c <= 0
            _ => false
          }
      }
  }
}

///|
fn try_compare(a : Value, b : Value) -> Int? {
  match (a, b) {
    (Value::Int(x), Value::Int(y)) => Some(cmp_int(x, y))
    (Value::Float(x), Value::Float(y)) => Some(cmp_double(x, y))
    (Value::Int(x), Value::Float(y)) => Some(cmp_double(x.to_double(), y))
    (Value::Float(x), Value::Int(y)) => Some(cmp_double(x, y.to_double()))
    (Value::Text(x), Value::Text(y)) => Some(x.compare(y))
    (Value::Bool(x), Value::Bool(y)) =>
      Some(if x == y { 0 } else if x { 1 } else { -1 })
    (Value::Null, Value::Null) => Some(0)
    _ => None
  }
}

///|
fn cmp_int(x : Int, y : Int) -> Int {
  if x < y {
    -1
  } else if x > y {
    1
  } else {
    0
  }
}

///|
fn cmp_double(x : Double, y : Double) -> Int {
  if x < y {
    -1
  } else if x > y {
    1
  } else {
    0
  }
}

///|
fn like_match(s : String, pattern : String) -> Bool {
  like_at(s.to_array(), 0, pattern.to_array(), 0)
}

///|
fn like_at(s : Array[Char], si : Int, p : Array[Char], pi : Int) -> Bool {
  if pi >= p.length() {
    return si >= s.length()
  }
  match p.get(pi) {
    None => si >= s.length()
    Some('%') =>
      like_at(s, si, p, pi + 1) ||
      (si < s.length() && like_at(s, si + 1, p, pi))
    Some('_') => si < s.length() && like_at(s, si + 1, p, pi + 1)
    Some(ch) =>
      match s.get(si) {
        None => false
        Some(sc) => sc == ch && like_at(s, si + 1, p, pi + 1)
      }
  }
}

///|
fn find_assignment(assignments : Array[Assignment], column : String) -> Value? {
  for a in assignments {
    if a.column.name == column {
      return Some(a.value)
    }
  }
  None
}

///|
fn apply_assignments(
  row : Array[Value],
  columns : Array[String],
  assignments : Array[Assignment],
) -> Array[Value] {
  let out = []
  for i, v in row {
    match columns.get(i) {
      None => out.push(v)
      Some(col) =>
        match find_assignment(assignments, col) {
          None => out.push(v)
          Some(nv) => out.push(nv)
        }
    }
  }
  out
}

///|
fn apply_limit_offset(
  rows : Array[Array[Value]],
  limit : Int?,
  offset : Int?,
) -> Array[Array[Value]] {
  let start = match offset {
    None => 0
    Some(o) => o
  }
  let end = match limit {
    None => rows.length()
    Some(l) => start + l
  }
  let out = []
  for i, row in rows {
    if i >= start && i < end {
      out.push(row)
    }
  }
  out
}

///|
fn row_compare(
  a : Array[Value],
  b : Array[Value],
  columns : Array[String],
  orders : Array[Order],
) -> Int {
  for order in orders {
    match order {
      Order::Asc(col) => {
        let c = value_cmp(
          column_value(col, columns, a),
          column_value(col, columns, b),
        )
        if c != 0 {
          return c
        }
      }
      Order::Desc(col) => {
        let c = value_cmp(
          column_value(col, columns, a),
          column_value(col, columns, b),
        )
        if c != 0 {
          return -c
        }
      }
    }
  }
  0
}

///|
fn value_cmp(a : Value?, b : Value?) -> Int {
  match (a, b) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) =>
      match try_compare(x, y) {
        None => 0
        Some(c) => c
      }
  }
}

///|
fn project(
  rows : Array[Array[Value]],
  columns : Array[String],
  sel : Array[ColumnRef],
) -> Array[Row] {
  if sel.is_empty() {
    return rows.map(fn(r) { Row::new(columns, r) })
  }
  let out_cols = sel.map(fn(c) { c.name })
  rows.map(fn(r) {
    let vals = sel.map(fn(c) {
      match column_value(c, columns, r) {
        None => Value::Null
        Some(v) => v
      }
    })
    Row::new(out_cols, vals)
  })
}

///|
/// The column label the in-memory backend gives an aggregate result.
fn aggregate_label(agg : Aggregate) -> String {
  match agg {
    Aggregate::CountAll => "count"
    Aggregate::Count(_) => "count"
    Aggregate::Sum(_) => "sum"
    Aggregate::Avg(_) => "avg"
    Aggregate::Min(_) => "min"
    Aggregate::Max(_) => "max"
  }
}

///|
/// Evaluate an aggregate over the already-filtered rows.
fn aggregate_value(
  agg : Aggregate,
  columns : Array[String],
  rows : Array[Array[Value]],
) -> Value {
  match agg {
    Aggregate::CountAll => Value::Int(rows.length())
    Aggregate::Count(col) =>
      Value::Int(
        rows.fold(init=0, fn(acc, row) {
          match column_value(col, columns, row) {
            None => acc
            Some(Value::Null) => acc
            Some(_) => acc + 1
          }
        }),
      )
    Aggregate::Sum(col) =>
      sum_values(rows.map(fn(row) { column_value(col, columns, row) }))
    Aggregate::Avg(col) =>
      avg_values(rows.map(fn(row) { column_value(col, columns, row) }))
    Aggregate::Min(col) =>
      extreme_value(
        rows.map(fn(row) { column_value(col, columns, row) }),
        false,
      )
    Aggregate::Max(col) =>
      extreme_value(rows.map(fn(row) { column_value(col, columns, row) }), true)
  }
}

///|
/// Sum numeric values; non-numeric and `null` values are skipped. Returns
/// `null` when there is nothing to sum.
fn sum_values(vals : Array[Value?]) -> Value {
  let mut int_sum = 0
  let mut float_sum = 0.0
  let mut count = 0
  let mut has_float = false
  for v in vals {
    match v {
      Some(Value::Int(n)) => {
        int_sum = int_sum + n
        count = count + 1
      }
      Some(Value::Float(f)) => {
        float_sum = float_sum + f
        has_float = true
        count = count + 1
      }
      _ => ()
    }
  }
  if count == 0 {
    Value::Null
  } else if has_float {
    Value::Float(float_sum + int_sum.to_double())
  } else {
    Value::Int(int_sum)
  }
}

///|
/// Average numeric values; returns a `Float`, or `null` when empty.
fn avg_values(vals : Array[Value?]) -> Value {
  let mut sum = 0.0
  let mut count = 0
  for v in vals {
    match v {
      Some(Value::Int(n)) => {
        sum = sum + n.to_double()
        count = count + 1
      }
      Some(Value::Float(f)) => {
        sum = sum + f
        count = count + 1
      }
      _ => ()
    }
  }
  if count == 0 {
    Value::Null
  } else {
    Value::Float(sum / count.to_double())
  }
}

///|
/// The minimum (`want_max == false`) or maximum (`want_max == true`) value,
/// comparing same-typed values only.
fn extreme_value(vals : Array[Value?], want_max : Bool) -> Value {
  let mut best : Value? = None
  for v in vals {
    match v {
      None => ()
      Some(Value::Null) => ()
      Some(x) =>
        match best {
          None => best = Some(x)
          Some(b) =>
            match try_compare(x, b) {
              None => ()
              Some(c) =>
                if (want_max && c > 0) || (!want_max && c < 0) {
                  best = Some(x)
                }
            }
        }
    }
  }
  match best {
    None => Value::Null
    Some(v) => v
  }
}

///|
/// Evaluate a grouped query: rows are bucketed by the grouping columns, then
/// each bucket collapses into one row (an aggregate over the bucket, or the
/// distinct grouping key when there is no aggregate).
fn mem_select_grouped(
  mem : Memory,
  tables : Array[String],
  columns : Array[String],
  query : Select,
  filtered : Array[Array[Value]],
) -> Array[Row] raise OrmError {
  let groups = group_rows(filtered, columns, query.group_by)
  let group_cols = query.group_by.map(fn(c) { c.name })
  let out_cols = match query.aggregate {
    None => group_cols
    Some(agg) => group_cols + [aggregate_label(agg)]
  }
  let out_rows : Array[Array[Value]] = []
  for (key, group) in groups {
    if matches(mem, query.having, tables, group_cols, key, None) {
      match query.aggregate {
        Some(agg) => out_rows.push(key + [aggregate_value(agg, columns, group)])
        None => out_rows.push(key)
      }
    }
  }
  if !query.orders.is_empty() {
    out_rows.sort_by(fn(a, b) { row_compare(a, b, out_cols, query.orders) })
  }
  let limited = apply_limit_offset(out_rows, query.limit, query.offset)
  limited.map(fn(r) { Row::new(out_cols, r) })
}

///|
/// Bucket rows by the values of the grouping columns, preserving first-seen
/// order of each key. Each element is `(key values, the rows in that bucket)`.
fn group_rows(
  rows : Array[Array[Value]],
  columns : Array[String],
  group_cols : Array[ColumnRef],
) -> Array[(Array[Value], Array[Array[Value]])] {
  let groups : Array[(Array[Value], Array[Array[Value]])] = []
  for row in rows {
    let key = group_cols.map(fn(c) {
      match column_value(c, columns, row) {
        None => Value::Null
        Some(v) => v
      }
    })
    match find_group_index(groups, key) {
      Some(i) => {
        let (k, g) = groups[i]
        groups[i] = (k, g + [row])
      }
      None => groups.push((key, [row]))
    }
  }
  groups
}

///|
fn find_group_index(
  groups : Array[(Array[Value], Array[Array[Value]])],
  key : Array[Value],
) -> Int? {
  for i in 0..<groups.length() {
    let (k, _) = groups[i]
    if key_equal(k, key) {
      return Some(i)
    }
  }
  None
}

///|
fn key_equal(a : Array[Value], b : Array[Value]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}
