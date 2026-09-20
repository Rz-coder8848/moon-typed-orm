///|
/// Smoke test through the public API. Downstream consumption is exercised by
/// the `cmd/` executables, which import this package from outside.
test "public api renders and runs" {
  let db = Memory::new()
  try! db.create_table("users", ["id", "name"])

  let id : Column[Int] = Column::new("users", "id")
  let name : Column[String] = Column::new("users", "name")

  let q = Select::from("users").where_(name.eq("alice"))
  let stmt = try! q.build()
  assert_eq(
    stmt.to_sql(),
    "SELECT * FROM \"users\" WHERE \"users\".\"name\" = ?",
  )

  let _ = try! db.insert(
    Insert::into("users").set(id.set(1)).set(name.set("alice")),
  )
  let rows = try! db.select(q)
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].get("id"), Some(Value::int(1)))
  assert_eq(rows[0].get("name"), Some(Value::text("alice")))
}
