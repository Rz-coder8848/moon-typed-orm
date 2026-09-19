///|
/// White-box tests for the SQLite backend. These need the `native` target and a
/// C toolchain; run with `moon test --target native`.

///|
test "sqlite :memory: round-trips CRUD through Connection" {
  let db = try! Sqlite::open(":memory:")
  try! db.exec("CREATE TABLE users (id INTEGER, name TEXT, age INTEGER)")

  let id : @moonorm.Column[Int] = @moonorm.Column::new("users", "id")
  let name : @moonorm.Column[String] = @moonorm.Column::new("users", "name")
  let age : @moonorm.Column[Int] = @moonorm.Column::new("users", "age")

  let ins = try! db.insert(
    @moonorm.Insert::into("users")
    .set(id.set(1))
    .set(name.set("alice"))
    .set(age.set(30)),
  )
  assert_eq(ins.rows_affected, 1)
  assert_eq(ins.last_insert_id, Some(1))

  let rows = try! db.select(@moonorm.Select::from("users").where_(age.gte(18)))
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].get("name"), Some(@moonorm.Value::text("alice")))
  assert_eq(rows[0].get("age"), Some(@moonorm.Value::int(30)))
}

///|
test "sqlite binds null and float, and updates in place" {
  let db = try! Sqlite::open(":memory:")
  try! db.exec("CREATE TABLE t (id INTEGER, note TEXT, score REAL)")

  let id : @moonorm.Column[Int] = @moonorm.Column::new("t", "id")
  let note : @moonorm.Column[String] = @moonorm.Column::new("t", "note")
  let score : @moonorm.Column[Double] = @moonorm.Column::new("t", "score")

  let _ = try! db.insert(
    @moonorm.Insert::into("t")
    .set(id.set(1))
    .set(note.set("keep"))
    .set(score.set(1.5)),
  )
  let _ = try! db.insert(
    @moonorm.Insert::into("t").set(id.set(2)).set(note.set("drop")),
  )

  let rows = try! db.select(@moonorm.Select::from("t").where_(score.is_null()))
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].get("note"), Some(@moonorm.Value::text("drop")))

  let upd = try! db.update(
    @moonorm.Update::table("t").set(note.set("changed")).where_(id.eq(2)),
  )
  assert_eq(upd.rows_affected, 1)

  let _ = try! db.delete(@moonorm.Delete::from("t").where_(id.eq(1)))
  let left = try! db.select(@moonorm.Select::from("t"))
  assert_eq(left.length(), 1)
  assert_eq(left[0].get("note"), Some(@moonorm.Value::text("changed")))
}

///|
test "sqlite transactions commit and roll back" {
  let db = try! Sqlite::open(":memory:")
  try! db.exec("CREATE TABLE t (id INTEGER, name TEXT)")

  let id : @moonorm.Column[Int] = @moonorm.Column::new("t", "id")
  let name : @moonorm.Column[String] = @moonorm.Column::new("t", "name")

  // Rolled-back inserts are discarded.
  try! db.begin()
  let _ = try! db.insert(
    @moonorm.Insert::into("t").set(id.set(1)).set(name.set("a")),
  )
  try! db.rollback()
  let empty = try! db.select(@moonorm.Select::from("t"))
  assert_eq(empty.length(), 0)

  // Committed inserts persist.
  try! db.begin()
  let _ = try! db.insert(
    @moonorm.Insert::into("t").set(id.set(1)).set(name.set("a")),
  )
  try! db.commit()
  let one = try! db.select(@moonorm.Select::from("t"))
  assert_eq(one.length(), 1)
  assert_eq(one[0].get("name"), Some(@moonorm.Value::text("a")))
}
