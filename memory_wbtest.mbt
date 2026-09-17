///|
/// White-box tests for the in-memory backend.
test "memory full crud round trip" {
  let db = Memory::new()
  try! db.create_table("users", ["id", "name", "age"])

  let id : Column[Int] = Column::new("users", "id")
  let name : Column[String] = Column::new("users", "name")
  let age : Column[Int] = Column::new("users", "age")

  let _ = try! db.insert(
    Insert::into("users").set(id.set(1)).set(name.set("alice")).set(age.set(30)),
  )
  let _ = try! db.insert(
    Insert::into("users").set(id.set(2)).set(name.set("bob")).set(age.set(17)),
  )
  let _ = try! db.insert(
    Insert::into("users").set(id.set(3)).set(name.set("carol")).set(age.set(25)),
  )

  let adults = try! db.select(
    Select::from("users").where_(age.gte(18)).order_by(age.desc()),
  )
  assert_eq(adults.length(), 2)
  assert_eq(adults[0].get("name"), Some(Value::Text("alice")))
  assert_eq(adults[1].get("name"), Some(Value::Text("carol")))

  let _ = try! db.update(
    Update::table("users").set(age.set(18)).where_(name.eq("bob")),
  )
  let bob = try! db.select(Select::from("users").where_(id.eq(2)))
  assert_eq(bob[0].get("age"), Some(Value::Int(18)))

  let _ = try! db.delete(Delete::from("users").where_(id.eq(1)))
  let all = try! db.select(Select::from("users"))
  assert_eq(all.length(), 2)
}

///|
test "memory projection and limit offset" {
  let db = Memory::new()
  try! db.create_table("t", ["id", "name"])
  let id : Column[Int] = Column::new("t", "id")
  let name : Column[String] = Column::new("t", "name")
  for i in 1..<6 {
    let _ = try! db.insert(
      Insert::into("t").set(id.set(i)).set(name.set("u\{i}")),
    )
  }
  let page = try! db.select(
    Select::from("t").order_by(id.asc()).limit(2).offset(2),
  )
  assert_eq(page.length(), 2)
  assert_eq(page[0].get("id"), Some(Value::Int(3)))
  assert_eq(page[0].get("name"), Some(Value::Text("u3")))
}

///|
test "memory in and null conditions" {
  let db = Memory::new()
  try! db.create_table("t", ["id", "note"])
  let id : Column[Int] = Column::new("t", "id")
  let note : Column[String] = Column::new("t", "note")
  let _ = try! db.insert(Insert::into("t").set(id.set(1)).set(note.set("a")))
  let _ = try! db.insert(Insert::into("t").set(id.set(2)))
  let _ = try! db.insert(Insert::into("t").set(id.set(3)).set(note.set("c")))

  let in_res = try! db.select(
    Select::from("t").where_(id.in_([1, 3])).order_by(id.asc()),
  )
  assert_eq(in_res.length(), 2)

  let null_res = try! db.select(Select::from("t").where_(note.is_null()))
  assert_eq(null_res.length(), 1)
  assert_eq(null_res[0].get("id"), Some(Value::Int(2)))
}

///|
test "memory like condition" {
  let db = Memory::new()
  try! db.create_table("t", ["name"])
  let name : Column[String] = Column::new("t", "name")
  let _ = try! db.insert(Insert::into("t").set(name.set("alice")))
  let _ = try! db.insert(Insert::into("t").set(name.set("bob")))
  let _ = try! db.insert(Insert::into("t").set(name.set("carol")))
  let hit = try! db.select(Select::from("t").where_(name.like("a%")))
  assert_eq(hit.length(), 1)
  assert_eq(hit[0].get("name"), Some(Value::Text("alice")))
}

///|
test "memory missing table raises" {
  let db = Memory::new()
  try {
    let _ = db.select(Select::from("nope"))
    panic()
  } catch {
    OrmError::Backend(_) => ()
    _ => panic()
  }
}

///|
test "memory raw condition rejected" {
  let db = Memory::new()
  try! db.create_table("t", ["x"])
  try {
    let _ = db.select(Select::from("t").where_(Condition::raw("1 = 1")))
    panic()
  } catch {
    OrmError::Backend(_) => ()
    _ => panic()
  }
}

///|
test "memory duplicate table raises" {
  let db = Memory::new()
  try! db.create_table("t", ["x"])
  try {
    db.create_table("t", ["x"])
    panic()
  } catch {
    OrmError::Backend(_) => ()
    _ => panic()
  }
}
