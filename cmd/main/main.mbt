///|
/// Runnable demo. Builds queries, renders one to SQL, and runs the rest against
/// the in-memory backend to show the full CRUD round-trip.
///
/// Run with `moon run cmd/main`.
fn main {
  let db = @moonorm.Memory::new()
  try! db.create_table("users", ["id", "name", "email", "age"])

  let id : @moonorm.Column[Int] = @moonorm.Column::new("users", "id")
  let name : @moonorm.Column[String] = @moonorm.Column::new("users", "name")
  let email : @moonorm.Column[String] = @moonorm.Column::new("users", "email")
  let age : @moonorm.Column[Int] = @moonorm.Column::new("users", "age")

  // Seed four users.
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

  // The same query, rendered to SQL and run in-memory.
  let adults = @moonorm.Select::from("users")
    .where_(age.gte(18))
    .order_by(age.desc())
    .limit(3)
  let adults_sql = try! adults.build()
  println("SQL: \{adults_sql.to_sql()}")

  println("adults (age >= 18, top 3):")
  let adult_rows = try! db.select(adults)
  for row in adult_rows {
    println("  \{format_row(row)}")
  }

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
