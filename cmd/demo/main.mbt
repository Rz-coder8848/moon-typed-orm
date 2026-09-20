///|
/// Flagship demo: walks the whole feature set against the in-memory backend.
/// Each section renders the SQL first — to show values stay bound as parameters,
/// never spliced into the text — then runs the same query in-memory.
///
/// Run with `moon run cmd/demo`.
fn main {
  let db = @moonorm.Memory::new()
  try! db.create_table("users", ["id", "name", "age", "city"])
  try! db.create_table("orders", ["id", "user_id", "amount"])

  let id : @moonorm.Column[Int] = @moonorm.Column::new("users", "id")
  let name : @moonorm.Column[String] = @moonorm.Column::new("users", "name")
  let age : @moonorm.Column[Int] = @moonorm.Column::new("users", "age")
  let city : @moonorm.Column[String] = @moonorm.Column::new("users", "city")
  let oid : @moonorm.Column[Int] = @moonorm.Column::new("orders", "id")
  let user_id : @moonorm.Column[Int] = @moonorm.Column::new("orders", "user_id")
  let amount : @moonorm.Column[Double] = @moonorm.Column::new("orders", "amount")

  seed_users(db, id, name, age, city)
  seed_orders(db, oid, user_id, amount)

  // Injection safety: a value carrying SQL keywords stays a bound value.
  let injected = "alice' OR 1=1 --"
  let stmt = try! @moonorm.Select::from("users").where_(name.eq(injected)).build()
  println("=== injection safety ===")
  println("sql:    \{stmt.to_sql()}")
  println("params: \{format_params(stmt.to_params())}")

  // Filter + order + limit.
  let adults = @moonorm.Select::from("users")
    .where_(age.gte(18))
    .order_by(age.desc())
    .limit(3)
  println("=== filter / order / limit ===")
  println("sql: \{try! adults.build().to_sql()}")
  print_rows(try! db.select(adults), ["id", "name", "age", "city"])

  // Aggregates.
  println("=== aggregate: count / avg ===")
  let cnt = @moonorm.Select::from("users").count()
  println("sql: \{try! cnt.build().to_sql()}")
  print_rows(try! db.select(cnt), ["count"])
  let avg = @moonorm.Select::from("users").avg(age)
  println("sql: \{try! avg.build().to_sql()}")
  print_rows(try! db.select(avg), ["avg"])

  // GROUP BY (+ HAVING rendered for a SQL driver; the in-memory backend
  // evaluates HAVING over grouping columns only).
  println("=== group by (+ having) ===")
  let by_city = @moonorm.Select::from("users").group_by(city).count()
  println("sql: \{try! by_city.build().to_sql()}")
  print_rows(try! db.select(by_city), ["city", "count"])
  let having_sql = try! by_city.having(@moonorm.Condition::raw("COUNT(*) > 1")).build()
  println("sql (having): \{having_sql.to_sql()}")

  // Joins.
  println("=== inner join ===")
  let inner = @moonorm.Select::from("users").join("orders", user_id.eq_col(id))
  println("sql: \{try! inner.build().to_sql()}")
  print_rows(try! db.select(inner), ["users.id", "users.name", "orders.id", "orders.amount"])
  println("=== left join ===")
  let left = @moonorm.Select::from("orders").left_join("users", user_id.eq_col(id))
  println("sql: \{try! left.build().to_sql()}")
  print_rows(try! db.select(left), ["orders.id", "orders.user_id", "users.id", "users.name"])

  // Subqueries.
  println("=== subquery: IN ===")
  let paid = @moonorm.Select::from("orders")
    .where_(amount.gt(5.0))
    .columns([user_id.to_ref()])
  let q_in = @moonorm.Select::from("users").where_(id.in_select(paid))
  println("sql: \{try! q_in.build().to_sql()}")
  print_rows(try! db.select(q_in), ["id", "name"])

  println("=== subquery: correlated EXISTS ===")
  let has_order = @moonorm.Select::from("orders").where_(user_id.eq_col(id))
  let q_exists = @moonorm.Select::from("users").where_(@moonorm.Condition::exists(has_order))
  println("sql: \{try! q_exists.build().to_sql()}")
  print_rows(try! db.select(q_exists), ["id", "name"])

  println("=== subquery: scalar (above average age) ===")
  let q_scalar = @moonorm.Select::from("users")
    .where_(age.gt_sub(@moonorm.Select::from("users").avg(age)))
  println("sql: \{try! q_scalar.build().to_sql()}")
  print_rows(try! db.select(q_scalar), ["id", "name", "age"])

  println("=== subquery: correlated NOT EXISTS ===")
  let q_none = @moonorm.Select::from("users")
    .where_(@moonorm.Condition::exists(has_order).not_())
  println("sql: \{try! q_none.build().to_sql()}")
  print_rows(try! db.select(q_none), ["id", "name"])
}

///|
fn seed_users(
  db : @moonorm.Memory,
  id : @moonorm.Column[Int],
  name : @moonorm.Column[String],
  age : @moonorm.Column[Int],
  city : @moonorm.Column[String],
) -> Unit {
  for (i, n, a, c) in [
    (1, "alice", 30, "sh"),
    (2, "bob", 17, "bj"),
    (3, "carol", 25, "sh"),
    (4, "dave", 41, "gz"),
  ] {
    let _ = try! db.insert(
      @moonorm.Insert::into("users")
      .set(id.set(i))
      .set(name.set(n))
      .set(age.set(a))
      .set(city.set(c)),
    )
  }
}

///|
fn seed_orders(
  db : @moonorm.Memory,
  oid : @moonorm.Column[Int],
  user_id : @moonorm.Column[Int],
  amount : @moonorm.Column[Double],
) -> Unit {
  for (i, u, amt) in [
    (1, 1, 12.5),
    (2, 3, 8.0),
    (3, 99, 3.0),
  ] {
    let _ = try! db.insert(
      @moonorm.Insert::into("orders")
      .set(oid.set(i))
      .set(user_id.set(u))
      .set(amount.set(amt)),
    )
  }
}

///|
fn print_rows(rows : Array[@moonorm.Row], columns : Array[String]) -> Unit {
  for row in rows {
    println("  " + columns.map(fn(c) { format_value(row.get(c)) }).join(" | "))
  }
}

///|
fn format_params(params : Array[@moonorm.Value]) -> String {
  params.map(fn(v) { format_value(Some(v)) }).join(", ")
}

///|
fn format_value(v : @moonorm.Value?) -> String {
  match v {
    None => "<missing>"
    Some(@moonorm.Value::Null) => "null"
    Some(@moonorm.Value::Bool(b)) => b.to_string()
    Some(@moonorm.Value::Int(n)) => n.to_string()
    Some(@moonorm.Value::Float(f)) => f.to_string()
    Some(@moonorm.Value::Text(s)) => s
    Some(@moonorm.Value::Blob(_)) => "<blob>"
  }
}
