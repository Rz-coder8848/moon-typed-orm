///|
/// Runnable demo for the SQLite backend. Mirrors `cmd/main` (the in-memory
/// demo) with the same query-builder calls — only the backend differs, which is
/// the replaceable [`@moonorm.Connection`] boundary. A real SQL backend differs
/// from the in-memory store in exactly two places shown here: raw DDL via
/// `exec`, and explicit transactions via `begin` / `commit` / `rollback`.
///
/// Run with `moon run cmd/sqlite_demo --target native` (needs a C toolchain).
fn main {
  let db = try! @sqlite.Sqlite::open(":memory:")
  try! db.exec(
    "CREATE TABLE users (id INTEGER, name TEXT, email TEXT, age INTEGER)",
  )

  let id : @moonorm.Column[Int] = @moonorm.Column::new("users", "id")
  let name : @moonorm.Column[String] = @moonorm.Column::new("users", "name")
  let email : @moonorm.Column[String] = @moonorm.Column::new("users", "email")
  let age : @moonorm.Column[Int] = @moonorm.Column::new("users", "age")

  // Seed four users inside a transaction.
  try! db.begin()
  let _ = try! db.insert(
    @moonorm.Insert::into("users")
    .set(id.set(1))
    .set(name.set("alice"))
    .set(email.set("alice@example.com"))
    .set(age.set(30)),
  )
  let _ = try! db.insert(
    @moonorm.Insert::into("users")
    .set(id.set(2))
    .set(name.set("bob"))
    .set(email.set("bob@example.com"))
    .set(age.set(17)),
  )
  let _ = try! db.insert(
    @moonorm.Insert::into("users")
    .set(id.set(3))
    .set(name.set("carol"))
    .set(email.set("carol@example.com"))
    .set(age.set(25)),
  )
  let _ = try! db.insert(
    @moonorm.Insert::into("users")
    .set(id.set(4))
    .set(name.set("dave"))
    .set(email.set("dave@example.com"))
    .set(age.set(41)),
  )
  try! db.commit()

  // The same query, rendered to SQL and run against SQLite.
  let adults = @moonorm.Select::from("users")
    .where_(age.gte(18))
    .order_by(age.desc())
    .limit(3)
  println("SQL: \{try! adults.build().to_sql()}")

  println("adults (age >= 18, top 3):")
  let adult_rows = try! db.select(adults)
  for row in adult_rows {
    println("  \{format_row(row)}")
  }

  // LEFT JOIN: an order with no matching user still keeps its left row.
  try! db.exec("CREATE TABLE orders (id INTEGER, user_id INTEGER, amount REAL)")
  let oid : @moonorm.Column[Int] = @moonorm.Column::new("orders", "id")
  let user_id : @moonorm.Column[Int] = @moonorm.Column::new("orders", "user_id")
  let amount : @moonorm.Column[Double] = @moonorm.Column::new("orders", "amount")
  let _ = try! db.insert(
    @moonorm.Insert::into("orders")
    .set(oid.set(1))
    .set(user_id.set(1))
    .set(amount.set(12.5)),
  )
  let _ = try! db.insert(
    @moonorm.Insert::into("orders")
    .set(oid.set(2))
    .set(user_id.set(99))
    .set(amount.set(3.0)),
  )
  let joined = @moonorm.Select::from("orders").left_join("users", user_id.eq_col(id))
  println("SQL (LEFT JOIN): \{try! joined.build().to_sql()}")

  let _ = try! db.update(
    @moonorm.Update::table("users").set(age.set(18)).where_(name.eq("bob")),
  )
  let _ = try! db.delete(@moonorm.Delete::from("users").where_(id.eq(4)))

  println("after update + delete:")
  let all_rows = try! db.select(
    @moonorm.Select::from("users").order_by(id.asc()),
  )
  for row in all_rows {
    println("  \{format_row(row)}")
  }

  // Roll back uncommitted work.
  try! db.begin()
  let _ = try! db.insert(
    @moonorm.Insert::into("users").set(id.set(9)).set(name.set("ghost")),
  )
  try! db.rollback()

  db.close()
}

///|
fn format_row(row : @moonorm.Row) -> String {
  let id = format_value(row.get("id"))
  let name = format_value(row.get("name"))
  let age = format_value(row.get("age"))
  "\{id} | \{name} | \{age}"
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
