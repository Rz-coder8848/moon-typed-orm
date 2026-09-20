///|
/// White-box tests for the SQL builders. These pin the exact SQL text and
/// parameter order, since the builders are the public contract of the library.
test "value type names" {
  assert_eq(Value::Null.type_name(), "null")
  assert_eq(Value::Int(1).type_name(), "int")
  assert_eq(Value::Float(1.5).type_name(), "float")
  assert_eq(Value::Text("x").type_name(), "text")
  assert_eq(Value::Bool(true).type_name(), "bool")
}

///|
test "select defaults to star with no filters" {
  let stmt = try! Select::from("users").build()
  assert_eq(stmt.sql, "SELECT * FROM \"users\"")
  assert_true(stmt.params.is_empty())
}

///|
test "select renders where order limit offset" {
  let age : Column[Int] = Column::new("users", "age")
  let stmt = try! Select::from("users")
    .where_(age.gt(18))
    .order_by(age.desc())
    .limit(10)
    .offset(5)
    .build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" WHERE \"users\".\"age\" > ? ORDER BY \"users\".\"age\" DESC LIMIT 10 OFFSET 5",
  )
  assert_eq(stmt.params, [Value::Int(18)])
}

///|
test "select with explicit columns" {
  let id : Column[Int] = Column::new("users", "id")
  let email : Column[String] = Column::new("users", "email")
  let stmt = try! Select::from("users")
    .columns([id.to_ref(), email.to_ref()])
    .build()
  assert_eq(
    stmt.sql,
    "SELECT \"users\".\"id\", \"users\".\"email\" FROM \"users\"",
  )
}

///|
test "and or combine into parenthesized sql" {
  let age : Column[Int] = Column::new("users", "age")
  let name : Column[String] = Column::new("users", "name")
  let cond = age.gte(18).and_(name.eq("alice").or_(name.eq("bob")))
  let stmt = try! Select::from("users").where_(cond).build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" WHERE (\"users\".\"age\" >= ? AND (\"users\".\"name\" = ? OR \"users\".\"name\" = ?))",
  )
  assert_eq(stmt.params, [
    Value::Int(18),
    Value::Text("alice"),
    Value::Text("bob"),
  ])
}

///|
test "in and null conditions" {
  let id : Column[Int] = Column::new("users", "id")
  let name : Column[String] = Column::new("users", "name")
  let cond = id.in_([1, 2, 3]).and_(name.is_null())
  let stmt = try! Select::from("users").where_(cond).build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" WHERE (\"users\".\"id\" IN (?, ?, ?) AND \"users\".\"name\" IS NULL)",
  )
  assert_eq(stmt.params, [Value::Int(1), Value::Int(2), Value::Int(3)])
}

///|
test "not and raw conditions" {
  let age : Column[Int] = Column::new("users", "age")
  let cond = age.is_null().not_().and_(Condition::raw("age > 0"))
  let stmt = try! Select::from("users").where_(cond).build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" WHERE ((NOT \"users\".\"age\" IS NULL) AND age > 0)",
  )
  assert_true(stmt.params.is_empty())
}

///|
test "insert renders placeholders" {
  let email : Column[String] = Column::new("users", "email")
  let age : Column[Int] = Column::new("users", "age")
  let stmt = try! Insert::into("users")
    .set(email.set("a@b.com"))
    .set(age.set(30))
    .build()
  assert_eq(
    stmt.sql,
    "INSERT INTO \"users\" (\"email\", \"age\") VALUES (?, ?)",
  )
  assert_eq(stmt.params, [Value::Text("a@b.com"), Value::Int(30)])
}

///|
test "update renders set and where" {
  let age : Column[Int] = Column::new("users", "age")
  let stmt = try! Update::table("users")
    .set(age.set(31))
    .where_(age.eq(30))
    .build()
  assert_eq(
    stmt.sql,
    "UPDATE \"users\" SET \"age\" = ? WHERE \"users\".\"age\" = ?",
  )
  assert_eq(stmt.params, [Value::Int(31), Value::Int(30)])
}

///|
test "delete renders where" {
  let age : Column[Int] = Column::new("users", "age")
  let stmt = try! Delete::from("users").where_(age.lt(18)).build()
  assert_eq(stmt.sql, "DELETE FROM \"users\" WHERE \"users\".\"age\" < ?")
  assert_eq(stmt.params, [Value::Int(18)])
}

///|
test "insert without assignments raises" {
  try {
    let _ = Insert::into("users").build()
    panic()
  } catch {
    OrmError::InvalidQuery(_) => ()
    _ => panic()
  }
}

///|
test "empty table name raises" {
  try {
    let _ = Select::from("").build()
    panic()
  } catch {
    OrmError::InvalidIdentifier(_) => ()
    _ => panic()
  }
}

///|
test "row get by column name and index" {
  let row = Row::new(["id", "email"], [Value::Int(1), Value::Text("a@b.com")])
  assert_eq(row.get("email"), Some(Value::Text("a@b.com")))
  assert_eq(row.get("missing"), None)
  assert_eq(row.get_at(0), Some(Value::Int(1)))
  assert_eq(row.get_at(9), None)
}

///|
test "count star renders aggregate" {
  let stmt = try! Select::from("users").count().build()
  assert_eq(stmt.sql, "SELECT COUNT(*) FROM \"users\"")
  assert_true(stmt.params.is_empty())
}

///|
test "aggregates render column expressions" {
  let age : Column[Int] = Column::new("users", "age")
  let stmt = try! Select::from("users").where_(age.gte(18)).sum(age).build()
  assert_eq(
    stmt.sql,
    "SELECT SUM(\"users\".\"age\") FROM \"users\" WHERE \"users\".\"age\" >= ?",
  )
  assert_eq(stmt.params, [Value::Int(18)])
}

///|
test "group by renders grouping columns and aggregate" {
  let city : Column[String] = Column::new("users", "city")
  let stmt = try! Select::from("users").group_by(city).count().build()
  assert_eq(
    stmt.sql,
    "SELECT \"users\".\"city\", COUNT(*) FROM \"users\" GROUP BY \"users\".\"city\"",
  )
  assert_true(stmt.params.is_empty())
}

///|
test "having renders after group by with raw aggregate" {
  let city : Column[String] = Column::new("users", "city")
  let stmt = try! Select::from("users")
    .group_by(city)
    .count()
    .having(Condition::raw("COUNT(*) > 1"))
    .build()
  assert_eq(
    stmt.sql,
    "SELECT \"users\".\"city\", COUNT(*) FROM \"users\" GROUP BY \"users\".\"city\" HAVING COUNT(*) > 1",
  )
  assert_true(stmt.params.is_empty())
}

///|
test "inner join renders on condition with qualified columns" {
  let users : Column[Int] = Column::new("users", "id")
  let orders : Column[Int] = Column::new("orders", "user_id")
  let stmt = try! Select::from("users")
    .join("orders", orders.eq_col(users))
    .build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" INNER JOIN \"orders\" ON \"orders\".\"user_id\" = \"users\".\"id\"",
  )
  assert_true(stmt.params.is_empty())
}

///|
test "left and right join render their keywords" {
  let users : Column[Int] = Column::new("users", "id")
  let orders : Column[Int] = Column::new("orders", "user_id")
  let left = try! Select::from("users")
    .left_join("orders", orders.eq_col(users))
    .build()
  assert_eq(
    left.sql,
    "SELECT * FROM \"users\" LEFT JOIN \"orders\" ON \"orders\".\"user_id\" = \"users\".\"id\"",
  )
  let right = try! Select::from("users")
    .right_join("orders", orders.eq_col(users))
    .build()
  assert_eq(
    right.sql,
    "SELECT * FROM \"users\" RIGHT JOIN \"orders\" ON \"orders\".\"user_id\" = \"users\".\"id\"",
  )
}

///|
test "full join renders its keyword" {
  let users : Column[Int] = Column::new("users", "id")
  let orders : Column[Int] = Column::new("orders", "user_id")
  let stmt = try! Select::from("users")
    .full_join("orders", orders.eq_col(users))
    .build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" FULL JOIN \"orders\" ON \"orders\".\"user_id\" = \"users\".\"id\"",
  )
}

///|
test "where and having params concatenate in order" {
  let city : Column[String] = Column::new("users", "city")
  let age : Column[Int] = Column::new("users", "age")
  let stmt = try! Select::from("users")
    .where_(age.gt(18))
    .group_by(city)
    .having(city.ne(""))
    .build()
  assert_eq(
    stmt.sql,
    "SELECT \"users\".\"city\" FROM \"users\" WHERE \"users\".\"age\" > ? GROUP BY \"users\".\"city\" HAVING \"users\".\"city\" <> ?",
  )
  assert_eq(stmt.params, [Value::Int(18), Value::Text("")])
}

///|
test "in subquery renders a nested select with its params" {
  let users : Column[Int] = Column::new("users", "id")
  let user_id : Column[Int] = Column::new("orders", "user_id")
  let sub = Select::from("orders").where_(user_id.gt(0))
  let stmt = try! Select::from("users").where_(users.in_select(sub)).build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" WHERE \"users\".\"id\" IN (SELECT * FROM \"orders\" WHERE \"orders\".\"user_id\" > ?)",
  )
  assert_eq(stmt.params, [Value::Int(0)])
}

///|
test "exists subquery renders" {
  let stmt = try! Select::from("users")
    .where_(Condition::exists(Select::from("orders")))
    .build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" WHERE EXISTS (SELECT * FROM \"orders\")",
  )
  assert_true(stmt.params.is_empty())
}

///|
test "not exists renders via not_" {
  let stmt = try! Select::from("users")
    .where_(Condition::exists(Select::from("orders")).not_())
    .build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" WHERE (NOT EXISTS (SELECT * FROM \"orders\"))",
  )
  assert_true(stmt.params.is_empty())
}

///|
test "scalar subquery renders comparison" {
  let age : Column[Int] = Column::new("users", "age")
  let sub = Select::from("users").avg(age)
  let stmt = try! Select::from("users").where_(age.gt_sub(sub)).build()
  assert_eq(
    stmt.sql,
    "SELECT * FROM \"users\" WHERE \"users\".\"age\" > (SELECT AVG(\"users\".\"age\") FROM \"users\")",
  )
  assert_true(stmt.params.is_empty())
}
