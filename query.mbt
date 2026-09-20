///|
/// A rendered SQL statement: text with `?` placeholders plus bound parameters.
pub struct Statement {
  sql : String
  params : Array[Value]
} derive(Eq, @debug.Debug)

///|
/// The rendered SQL text.
pub fn Statement::to_sql(self : Statement) -> String {
  self.sql
}

///|
/// The bound parameters, in placeholder order.
pub fn Statement::to_params(self : Statement) -> Array[Value] {
  self.params
}

///|
/// A join: a right-hand table matched against the left on `on`, of a given
/// [`JoinKind`].
struct Join {
  table : String
  on : Condition
  kind : JoinKind
} derive(Eq, @debug.Debug)

///|
/// Build a `SELECT`.
pub struct Select {
  table : String
  columns : Array[ColumnRef]
  aggregate : Aggregate?
  condition : Condition?
  group_by : Array[ColumnRef]
  having : Condition?
  join : Join?
  orders : Array[Order]
  limit : Int?
  offset : Int?
} derive(Eq, @debug.Debug)

///|
pub fn Select::from(table : String) -> Select {
  {
    table,
    columns: [],
    aggregate: None,
    condition: None,
    group_by: [],
    having: None,
    join: None,
    orders: [],
    limit: None,
    offset: None,
  }
}

///|
/// Restrict to specific columns; omit to select all (`*`).
pub fn Select::columns(self : Select, columns : Array[ColumnRef]) -> Select {
  { ..self, columns, }
}

///|
pub fn Select::where_(self : Select, condition : Condition) -> Select {
  { ..self, condition: Some(condition), }
}

///|
pub fn Select::order_by(self : Select, order : Order) -> Select {
  { ..self, orders: self.orders + [order], }
}

///|
pub fn Select::limit(self : Select, limit : Int) -> Select {
  { ..self, limit: Some(limit), }
}

///|
pub fn Select::offset(self : Select, offset : Int) -> Select {
  { ..self, offset: Some(offset), }
}

///|
/// Aggregate all rows with `COUNT(*)`.
pub fn Select::count(self : Select) -> Select {
  { ..self, aggregate: Some(Aggregate::CountAll), }
}

///|
/// Count the non-null values of a column.
pub fn[T] Select::count_of(self : Select, column : Column[T]) -> Select {
  { ..self, aggregate: Some(Aggregate::Count(column.to_ref())), }
}

///|
/// Sum a numeric column.
pub fn[T] Select::sum(self : Select, column : Column[T]) -> Select {
  { ..self, aggregate: Some(Aggregate::Sum(column.to_ref())), }
}

///|
/// Average a numeric column.
pub fn[T] Select::avg(self : Select, column : Column[T]) -> Select {
  { ..self, aggregate: Some(Aggregate::Avg(column.to_ref())), }
}

///|
/// Minimum value of a column.
pub fn[T] Select::min(self : Select, column : Column[T]) -> Select {
  { ..self, aggregate: Some(Aggregate::Min(column.to_ref())), }
}

///|
/// Maximum value of a column.
pub fn[T] Select::max(self : Select, column : Column[T]) -> Select {
  { ..self, aggregate: Some(Aggregate::Max(column.to_ref())), }
}

///|
/// Group rows by a column. Repeated calls add more grouping columns; the
/// selected columns become the grouping columns (plus an aggregate, if any).
pub fn[T] Select::group_by(self : Select, column : Column[T]) -> Select {
  { ..self, group_by: self.group_by + [column.to_ref()], }
}

///|
/// Filter groups after aggregation. The in-memory backend can only address
/// grouping columns here; a SQL driver can also use [`Condition::raw`] to
/// reference an aggregate (for example `Condition::raw("COUNT(*) > 1")`).
pub fn Select::having(self : Select, condition : Condition) -> Select {
  { ..self, having: Some(condition), }
}

///|
/// Inner-join another table on a condition. Columns from either table stay
/// qualified, so an `on` condition can reference both (for example
/// `order.user_id.eq(user.id)`).
pub fn Select::join(self : Select, table : String, on : Condition) -> Select {
  { ..self, join: Some({ table, on, kind: JoinKind::Inner, }), }
}

///|
/// Left-join another table on a condition. Rows from the left table are kept
/// even when no row on the right matches (right-hand columns become null).
pub fn Select::left_join(
  self : Select,
  table : String,
  on : Condition,
) -> Select {
  { ..self, join: Some({ table, on, kind: JoinKind::Left, }), }
}

///|
/// Right-join another table on a condition. Rows from the right table are kept
/// even when no row on the left matches (left-hand columns become null).
pub fn Select::right_join(
  self : Select,
  table : String,
  on : Condition,
) -> Select {
  { ..self, join: Some({ table, on, kind: JoinKind::Right, }), }
}

///|
/// Full-join another table on a condition. Rows from either side are kept even
/// when no row on the other side matches (the missing side becomes null).
pub fn Select::full_join(
  self : Select,
  table : String,
  on : Condition,
) -> Select {
  { ..self, join: Some({ table, on, kind: JoinKind::Full, }), }
}

///|
pub fn Select::build(self : Select) -> Statement raise OrmError {
  validate_table(self.table)
  match self.join {
    Some(j) => validate_table(j.table)
    None => ()
  }
  let cols = if self.group_by.is_empty() {
    match self.aggregate {
      Some(agg) => render_aggregate(agg)
      None =>
        if self.columns.is_empty() {
          "*"
        } else {
          join_column_refs(self.columns)
        }
    }
  } else {
    let groups = join_column_refs(self.group_by)
    match self.aggregate {
      Some(agg) => "\{groups}, \{render_aggregate(agg)}"
      None => groups
    }
  }
  let (join_sql, join_params) = render_join(self.join)
  let (where_sql, where_params) = render_where(self.condition)
  let group_sql = render_group(self.group_by)
  let (having_sql, having_params) = render_having(self.having)
  let order_sql = render_order(self.orders)
  let limit_sql = match self.limit {
    None => ""
    Some(n) => " LIMIT \{n}"
  }
  let offset_sql = match self.offset {
    None => ""
    Some(n) => " OFFSET \{n}"
  }
  {
    sql: "SELECT \{cols} FROM \{quote_ident(self.table)}" +
    join_sql +
    where_sql +
    group_sql +
    having_sql +
    order_sql +
    limit_sql +
    offset_sql,
    params: join_params + where_params + having_params,
  }
}

///|
/// Build an `INSERT`.
pub struct Insert {
  table : String
  assignments : Array[Assignment]
}

///|
pub fn Insert::into(table : String) -> Insert {
  { table, assignments: [], }
}

///|
pub fn Insert::set(self : Insert, assignment : Assignment) -> Insert {
  { ..self, assignments: self.assignments + [assignment], }
}

///|
pub fn Insert::build(self : Insert) -> Statement raise OrmError {
  validate_table(self.table)
  if self.assignments.is_empty() {
    raise OrmError::InvalidQuery("INSERT needs at least one column assignment")
  }
  let cols = self.assignments.map(fn(a) { quote_ident(a.column.name) })
  let placeholders = self.assignments.map(fn(_) { "?" })
  let params = self.assignments.map(fn(a) { a.value })
  {
    sql: "INSERT INTO \{quote_ident(self.table)} (\{cols.join(", ")}) VALUES (\{placeholders.join(", ")})",
    params,
  }
}

///|
/// Build an `UPDATE`.
pub struct Update {
  table : String
  assignments : Array[Assignment]
  condition : Condition?
}

///|
pub fn Update::table(table : String) -> Update {
  { table, assignments: [], condition: None, }
}

///|
pub fn Update::set(self : Update, assignment : Assignment) -> Update {
  { ..self, assignments: self.assignments + [assignment], }
}

///|
pub fn Update::where_(self : Update, condition : Condition) -> Update {
  { ..self, condition: Some(condition), }
}

///|
pub fn Update::build(self : Update) -> Statement raise OrmError {
  validate_table(self.table)
  if self.assignments.is_empty() {
    raise OrmError::InvalidQuery("UPDATE needs at least one column assignment")
  }
  let sets = self.assignments.map(fn(a) { "\{quote_ident(a.column.name)} = ?" })
  let params = self.assignments.map(fn(a) { a.value })
  let (where_sql, where_params) = render_where(self.condition)
  {
    sql: "UPDATE \{quote_ident(self.table)} SET \{sets.join(", ")}" + where_sql,
    params: params + where_params,
  }
}

///|
/// Build a `DELETE`.
pub struct Delete {
  table : String
  condition : Condition?
}

///|
pub fn Delete::from(table : String) -> Delete {
  { table, condition: None, }
}

///|
pub fn Delete::where_(self : Delete, condition : Condition) -> Delete {
  { ..self, condition: Some(condition), }
}

///|
pub fn Delete::build(self : Delete) -> Statement raise OrmError {
  validate_table(self.table)
  let (where_sql, where_params) = render_where(self.condition)
  {
    sql: "DELETE FROM \{quote_ident(self.table)}" + where_sql,
    params: where_params,
  }
}

///|
fn render_where(
  condition : Condition?,
) -> (String, Array[Value]) raise OrmError {
  match condition {
    None => ("", [])
    Some(cond) => {
      let (sql, params) = render_condition(cond)
      (" WHERE " + sql, params)
    }
  }
}

///|
fn render_order(orders : Array[Order]) -> String {
  if orders.is_empty() {
    return ""
  }
  let parts = orders.map(fn(order) {
    match order {
      Order::Asc(col) => "\{quote_column(col)} ASC"
      Order::Desc(col) => "\{quote_column(col)} DESC"
    }
  })
  " ORDER BY " + parts.join(", ")
}

///|
fn render_group(group_by : Array[ColumnRef]) -> String {
  if group_by.is_empty() {
    return ""
  }
  " GROUP BY " + join_column_refs(group_by)
}

///|
fn render_having(having : Condition?) -> (String, Array[Value]) raise OrmError {
  match having {
    None => ("", [])
    Some(cond) => {
      let (sql, params) = render_condition(cond)
      (" HAVING " + sql, params)
    }
  }
}

///|
fn render_join(join : Join?) -> (String, Array[Value]) raise OrmError {
  match join {
    None => ("", [])
    Some(j) => {
      let (on_sql, on_params) = render_condition(j.on)
      (
        render_join_kind(j.kind) + " \{quote_ident(j.table)} ON \{on_sql}",
        on_params,
      )
    }
  }
}

///|
fn render_join_kind(kind : JoinKind) -> String {
  match kind {
    JoinKind::Inner => " INNER JOIN"
    JoinKind::Left => " LEFT JOIN"
    JoinKind::Right => " RIGHT JOIN"
    JoinKind::Full => " FULL JOIN"
  }
}

///|
fn render_aggregate(agg : Aggregate) -> String {
  match agg {
    Aggregate::CountAll => "COUNT(*)"
    Aggregate::Count(col) => "COUNT(\{quote_column(col)})"
    Aggregate::Sum(col) => "SUM(\{quote_column(col)})"
    Aggregate::Avg(col) => "AVG(\{quote_column(col)})"
    Aggregate::Min(col) => "MIN(\{quote_column(col)})"
    Aggregate::Max(col) => "MAX(\{quote_column(col)})"
  }
}

///|
fn render_condition(cond : Condition) -> (String, Array[Value]) raise OrmError {
  match cond {
    Condition::Compare(col, op, value) =>
      (quote_column(col) + " \{op_sql(op)} ?", [value])
    Condition::CompareCol(left, op, right) =>
      (quote_column(left) + " \{op_sql(op)} " + quote_column(right), [])
    Condition::CompareSub(col, op, sub) => {
      let stmt = sub.build()
      (quote_column(col) + " \{op_sql(op)} (" + stmt.sql + ")", stmt.params)
    }
    Condition::In(col, values) =>
      (
        quote_column(col) + " IN (" + values.map(fn(_) { "?" }).join(", ") + ")",
        values,
      )
    Condition::InSelect(col, sub) => {
      let stmt = sub.build()
      (quote_column(col) + " IN (" + stmt.sql + ")", stmt.params)
    }
    Condition::IsNull(col) => (quote_column(col) + " IS NULL", [])
    Condition::IsNotNull(col) => (quote_column(col) + " IS NOT NULL", [])
    Condition::Exists(sub) => {
      let stmt = sub.build()
      ("EXISTS (" + stmt.sql + ")", stmt.params)
    }
    Condition::And(a, b) => {
      let (a_sql, a_params) = render_condition(a)
      let (b_sql, b_params) = render_condition(b)
      ("(\{a_sql} AND \{b_sql})", a_params + b_params)
    }
    Condition::Or(a, b) => {
      let (a_sql, a_params) = render_condition(a)
      let (b_sql, b_params) = render_condition(b)
      ("(\{a_sql} OR \{b_sql})", a_params + b_params)
    }
    Condition::Not(a) => {
      let (a_sql, a_params) = render_condition(a)
      ("(NOT \{a_sql})", a_params)
    }
    Condition::Raw(sql) => (sql, [])
  }
}

///|
fn op_sql(op : CompareOp) -> String {
  match op {
    CompareOp::Eq => "="
    CompareOp::Ne => "<>"
    CompareOp::Gt => ">"
    CompareOp::Gte => ">="
    CompareOp::Lt => "<"
    CompareOp::Lte => "<="
    CompareOp::Like => "LIKE"
  }
}

///|
fn quote_column(col : ColumnRef) -> String {
  quote_ident(col.table) + "." + quote_ident(col.name)
}

///|
fn join_column_refs(cols : Array[ColumnRef]) -> String {
  cols.map(fn(c) { quote_column(c) }).join(", ")
}

///|
fn quote_ident(ident : String) -> String {
  "\"" + ident + "\""
}

///|
fn validate_table(table : String) -> Unit raise OrmError {
  if table.is_empty() {
    raise OrmError::InvalidIdentifier(table)
  }
}
