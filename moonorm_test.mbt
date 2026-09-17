///|
/// Black-box smoke test: consume the package through its public API exactly as
/// a downstream user would.
test "public api renders and runs" {
  let db = @moonorm.Memory::new()
  try! db.create_table("users", ["id", "name"])

  let id : @moonorm.Column[Int] = @moonorm.Column::new("users", "id")
  let name : @moonorm.Column[String] = @moonorm.Column::new("users", "name")

  let q = @moonorm.Select::from("users").where_(name.eq("alice"))
  let stmt = try! q.build()
  assert_eq(
    stmt.to_sql(),
    "SELECT * FROM \"users\" WHERE \"users\".\"name\" = ?",
  )

  let _ = try! db.insert(
    @moonorm.Insert::into("users").set(id.set(1)).set(name.set("alice")),
  )
  let rows = try! db.select(q)
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].get("id"), Some(@moonorm.Value::int(1)))
  assert_eq(rows[0].get("name"), Some(@moonorm.Value::text("alice")))
}
