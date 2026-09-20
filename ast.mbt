///|
/// Identifies a column by its qualified table and name.
pub struct ColumnRef {
  table : String
  name : String
} derive(Eq, @debug.Debug)

///|
/// A typed reference to a column.
///
/// The type parameter `T` is a compile-time marker that pins the column to a
/// MoonBit type so comparisons stay type-checked; it never appears in the SQL
/// text. Build one with [`Column::new`], for example:
///
/// ```moonbit nocheck
/// let email : Column[String] = Column::new("users", "email")
/// ```
#warnings("-unused_type_variable")
pub struct Column[T] {
  reference : ColumnRef
}

///|
/// Create a typed column reference.
pub fn[T] Column::new(table : String, name : String) -> Column[T] {
  { reference: { table, name, }, }
}

///|
pub fn[T] Column::table(self : Column[T]) -> String {
  self.reference.table
}

///|
pub fn[T] Column::name(self : Column[T]) -> String {
  self.reference.name
}

///|
/// The underlying untyped column reference.
pub fn[T] Column::to_ref(self : Column[T]) -> ColumnRef {
  self.reference
}

///|
/// Binary comparison operators.
pub enum CompareOp {
  Eq
  Ne
  Gt
  Gte
  Lt
  Lte
  Like
} derive(Eq, @debug.Debug)

///|
/// A boolean expression in a query.
pub enum Condition {
  Compare(ColumnRef, CompareOp, Value)
  CompareCol(ColumnRef, CompareOp, ColumnRef)
  CompareSub(ColumnRef, CompareOp, Select)
  In(ColumnRef, Array[Value])
  InSelect(ColumnRef, Select)
  IsNull(ColumnRef)
  IsNotNull(ColumnRef)
  Exists(Select)
  And(Condition, Condition)
  Or(Condition, Condition)
  Not(Condition)
  Raw(String)
} derive(Eq, @debug.Debug)

///|
/// Combine two conditions with `AND`.
pub fn Condition::and_(self : Condition, other : Condition) -> Condition {
  Condition::And(self, other)
}

///|
/// Combine two conditions with `OR`.
pub fn Condition::or_(self : Condition, other : Condition) -> Condition {
  Condition::Or(self, other)
}

///|
/// Negate a condition.
pub fn Condition::not_(self : Condition) -> Condition {
  Condition::Not(self)
}

///|
/// Escape hatch: a raw SQL fragment spliced into the `WHERE` clause as-is.
/// Prefer the typed helpers; use this only for operators the DSL doesn't model.
pub fn Condition::raw(sql : String) -> Condition {
  Condition::Raw(sql)
}

///|
/// `EXISTS (SELECT ...)` — true when the subquery returns at least one row.
/// Combine with [`Condition::not_`] for `NOT EXISTS`. Non-correlated only: the
/// subquery cannot reference the outer query's rows.
pub fn Condition::exists(sub : Select) -> Condition {
  Condition::Exists(sub)
}

///|
/// Sort direction.
pub enum Order {
  Asc(ColumnRef)
  Desc(ColumnRef)
} derive(Eq, @debug.Debug)

///|
/// An aggregate function over a column, or `COUNT(*)` over all rows.
pub enum Aggregate {
  CountAll
  Count(ColumnRef)
  Sum(ColumnRef)
  Avg(ColumnRef)
  Min(ColumnRef)
  Max(ColumnRef)
} derive(Eq, @debug.Debug)

///|
/// The kind of a join clause.
pub enum JoinKind {
  Inner
  Left
  Right
  Full
} derive(Eq, @debug.Debug)

///|
/// A column assignment used by `INSERT` and `UPDATE`.
pub struct Assignment {
  column : ColumnRef
  value : Value
} derive(Eq, @debug.Debug)

///|
pub fn[T : ToValue] Column::eq(self : Column[T], value : T) -> Condition {
  Condition::Compare(self.reference, CompareOp::Eq, value.to_value())
}

///|
pub fn[T : ToValue] Column::ne(self : Column[T], value : T) -> Condition {
  Condition::Compare(self.reference, CompareOp::Ne, value.to_value())
}

///|
pub fn[T : ToValue] Column::gt(self : Column[T], value : T) -> Condition {
  Condition::Compare(self.reference, CompareOp::Gt, value.to_value())
}

///|
pub fn[T : ToValue] Column::gte(self : Column[T], value : T) -> Condition {
  Condition::Compare(self.reference, CompareOp::Gte, value.to_value())
}

///|
pub fn[T : ToValue] Column::lt(self : Column[T], value : T) -> Condition {
  Condition::Compare(self.reference, CompareOp::Lt, value.to_value())
}

///|
pub fn[T : ToValue] Column::lte(self : Column[T], value : T) -> Condition {
  Condition::Compare(self.reference, CompareOp::Lte, value.to_value())
}

///|
pub fn[T : ToValue] Column::like(self : Column[T], value : T) -> Condition {
  Condition::Compare(self.reference, CompareOp::Like, value.to_value())
}

///|
/// Compare this column against another column (for example the `ON` condition
/// of a join). Both columns must share the same type.
pub fn[T] Column::eq_col(self : Column[T], other : Column[T]) -> Condition {
  Condition::CompareCol(self.reference, CompareOp::Eq, other.reference)
}

///|
/// Compare this column against a scalar subquery (`col = (SELECT ...)`).
pub fn[T] Column::eq_sub(self : Column[T], sub : Select) -> Condition {
  Condition::CompareSub(self.reference, CompareOp::Eq, sub)
}

///|
/// Compare this column against a scalar subquery (`col <> (SELECT ...)`).
pub fn[T] Column::ne_sub(self : Column[T], sub : Select) -> Condition {
  Condition::CompareSub(self.reference, CompareOp::Ne, sub)
}

///|
/// Compare this column against a scalar subquery (`col > (SELECT ...)`).
pub fn[T] Column::gt_sub(self : Column[T], sub : Select) -> Condition {
  Condition::CompareSub(self.reference, CompareOp::Gt, sub)
}

///|
/// Compare this column against a scalar subquery (`col >= (SELECT ...)`).
pub fn[T] Column::gte_sub(self : Column[T], sub : Select) -> Condition {
  Condition::CompareSub(self.reference, CompareOp::Gte, sub)
}

///|
/// Compare this column against a scalar subquery (`col < (SELECT ...)`).
pub fn[T] Column::lt_sub(self : Column[T], sub : Select) -> Condition {
  Condition::CompareSub(self.reference, CompareOp::Lt, sub)
}

///|
/// Compare this column against a scalar subquery (`col <= (SELECT ...)`).
pub fn[T] Column::lte_sub(self : Column[T], sub : Select) -> Condition {
  Condition::CompareSub(self.reference, CompareOp::Lte, sub)
}

///|
pub fn[T : ToValue] Column::in_(
  self : Column[T],
  values : Array[T],
) -> Condition {
  Condition::In(self.reference, values.map(fn(v) { v.to_value() }))
}

///|
/// Match this column against a single-column subquery (`col IN (SELECT ...)`).
/// The subquery selects one column; the in-memory backend uses its first. The
/// subquery is non-correlated: it cannot reference the outer query's rows.
pub fn[T] Column::in_select(self : Column[T], sub : Select) -> Condition {
  Condition::InSelect(self.reference, sub)
}

///|
pub fn[T] Column::is_null(self : Column[T]) -> Condition {
  Condition::IsNull(self.reference)
}

///|
pub fn[T] Column::is_not_null(self : Column[T]) -> Condition {
  Condition::IsNotNull(self.reference)
}

///|
pub fn[T] Column::asc(self : Column[T]) -> Order {
  Order::Asc(self.reference)
}

///|
pub fn[T] Column::desc(self : Column[T]) -> Order {
  Order::Desc(self.reference)
}

///|
pub fn[T : ToValue] Column::set(self : Column[T], value : T) -> Assignment {
  { column: self.reference, value: value.to_value(), }
}
