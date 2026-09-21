///|
/// White-box tests for the moondb backend. These run on the wasm-gc target and
/// need no database: the [`@db.MockDriver`] echo store stands in for any real
/// driver, so what is asserted is that the builder's SQL and bound values reach
/// the seam unchanged and the results map back onto the root package's types.

///|
test "moondb insert/select round-trip through the driver (echo store)" {
  let mock = @db.MockDriver::new()
  let db = Moondb::new(mock)

  let id : @moonorm.Column[Int] = @moonorm.Column::new("users", "id")
  let name : @moonorm.Column[String] = @moonorm.Column::new("users", "name")

  let ins = try! db.insert(
    @moonorm.Insert::into("users").set(id.set(1)).set(name.set("alice")),
  )
  assert_eq(ins.rows_affected, 1)
  assert_eq(ins.last_insert_id, Some(1))
  assert_eq(mock.row_count(), 1)

  let rows = try! db.select(@moonorm.Select::from("users"))
  assert_eq(rows.length(), 1)
  // MockDriver echoes the bound params back under c0, c1, ….
  assert_eq(rows[0].get("c0"), Some(@moonorm.Value::int(1)))
  assert_eq(rows[0].get("c1"), Some(@moonorm.Value::text("alice")))
}

///|
test "moondb maps every value kind both ways" {
  let mock = @db.MockDriver::new()
  let db = Moondb::new(mock)

  let id : @moonorm.Column[Int] = @moonorm.Column::new("t", "id")
  let score : @moonorm.Column[Double] = @moonorm.Column::new("t", "score")
  let active : @moonorm.Column[Bool] = @moonorm.Column::new("t", "active")
  let note : @moonorm.Column[String] = @moonorm.Column::new("t", "note")

  let _ = try! db.insert(
    @moonorm.Insert::into("t")
    .set(id.set(7))
    .set(score.set(1.5))
    .set(active.set(true))
    .set(note.set("hi")),
  )

  let rows = try! db.select(@moonorm.Select::from("t"))
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].get("c0"), Some(@moonorm.Value::int(7)))
  assert_eq(rows[0].get("c1"), Some(@moonorm.Value::float(1.5)))
  assert_eq(rows[0].get("c2"), Some(@moonorm.Value::bool(true)))
  assert_eq(rows[0].get("c3"), Some(@moonorm.Value::text("hi")))
}

///|
test "moondb delegates the transaction bracket to the driver" {
  let mock = @db.MockDriver::new()
  let db = Moondb::new(mock)

  let id : @moonorm.Column[Int] = @moonorm.Column::new("t", "id")
  let _ = try! db.insert(@moonorm.Insert::into("t").set(id.set(1)))

  // Work done inside a rolled-back transaction must vanish.
  try! db.begin()
  let _ = try! db.insert(@moonorm.Insert::into("t").set(id.set(2)))
  assert_eq(mock.row_count(), 2)
  try! db.rollback()
  assert_eq(mock.row_count(), 1)

  // Work done inside a committed transaction must persist.
  try! db.begin()
  let _ = try! db.insert(@moonorm.Insert::into("t").set(id.set(3)))
  try! db.commit()
  assert_eq(mock.row_count(), 2)
}

///|
test "moondb re-raises driver errors as OrmError::Backend" {
  let mock = @db.MockDriver::new()
  let db = Moondb::new(mock)

  // commit with no open transaction: the driver raises QueryError, the adapter
  // folds it into OrmError::Backend.
  try {
    db.commit()
    panic()
  } catch {
    @moonorm.OrmError::Backend(_) => ()
    _ => panic()
  }
}
