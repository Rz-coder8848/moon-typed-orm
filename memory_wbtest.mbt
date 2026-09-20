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

///|
test "memory aggregates over filtered rows" {
  let db = Memory::new()
  try! db.create_table("users", ["id", "age"])
  let id : Column[Int] = Column::new("users", "id")
  let age : Column[Int] = Column::new("users", "age")
  let _ = try! db.insert(Insert::into("users").set(id.set(1)).set(age.set(30)))
  let _ = try! db.insert(Insert::into("users").set(id.set(2)).set(age.set(17)))
  let _ = try! db.insert(Insert::into("users").set(id.set(3)).set(age.set(25)))

  let count = try! db.select(Select::from("users").count())
  assert_eq(count[0].get("count"), Some(Value::int(3)))

  let adult_sum = try! db.select(
    Select::from("users").where_(age.gte(18)).sum(age),
  )
  assert_eq(adult_sum[0].get("sum"), Some(Value::int(55)))

  let avg = try! db.select(Select::from("users").avg(age))
  assert_eq(avg[0].get("avg"), Some(Value::float(24.0)))

  let min = try! db.select(Select::from("users").min(age))
  assert_eq(min[0].get("min"), Some(Value::int(17)))

  let max = try! db.select(Select::from("users").max(age))
  assert_eq(max[0].get("max"), Some(Value::int(30)))
}

///|
test "memory group by with count aggregate" {
  let db = Memory::new()
  try! db.create_table("t", ["city", "name"])
  let city : Column[String] = Column::new("t", "city")
  let name : Column[String] = Column::new("t", "name")
  let _ = try! db.insert(
    Insert::into("t").set(city.set("SF")).set(name.set("a")),
  )
  let _ = try! db.insert(
    Insert::into("t").set(city.set("SF")).set(name.set("b")),
  )
  let _ = try! db.insert(
    Insert::into("t").set(city.set("NY")).set(name.set("c")),
  )
  let _ = try! db.insert(
    Insert::into("t").set(city.set("NY")).set(name.set("d")),
  )
  let _ = try! db.insert(
    Insert::into("t").set(city.set("NY")).set(name.set("e")),
  )

  let groups = try! db.select(
    Select::from("t").group_by(city).count().order_by(city.asc()),
  )
  assert_eq(groups.length(), 2)
  assert_eq(groups[0].get("city"), Some(Value::text("NY")))
  assert_eq(groups[0].get("count"), Some(Value::int(3)))
  assert_eq(groups[1].get("city"), Some(Value::text("SF")))
  assert_eq(groups[1].get("count"), Some(Value::int(2)))
}

///|
test "memory inner join round trip" {
  let db = Memory::new()
  try! db.create_table("users", ["id", "name"])
  try! db.create_table("orders", ["id", "user_id", "item"])
  let users_id : Column[Int] = Column::new("users", "id")
  let users_name : Column[String] = Column::new("users", "name")
  let orders_id : Column[Int] = Column::new("orders", "id")
  let orders_user_id : Column[Int] = Column::new("orders", "user_id")
  let orders_item : Column[String] = Column::new("orders", "item")

  let _ = try! db.insert(
    Insert::into("users").set(users_id.set(1)).set(users_name.set("alice")),
  )
  let _ = try! db.insert(
    Insert::into("users").set(users_id.set(2)).set(users_name.set("bob")),
  )
  let _ = try! db.insert(
    Insert::into("orders")
    .set(orders_id.set(100))
    .set(orders_user_id.set(1))
    .set(orders_item.set("book")),
  )
  let _ = try! db.insert(
    Insert::into("orders")
    .set(orders_id.set(101))
    .set(orders_user_id.set(1))
    .set(orders_item.set("pen")),
  )
  let _ = try! db.insert(
    Insert::into("orders")
    .set(orders_id.set(102))
    .set(orders_user_id.set(2))
    .set(orders_item.set("cup")),
  )

  let rows = try! db.select(
    Select::from("users").join("orders", orders_user_id.eq_col(users_id)),
  )
  assert_eq(rows.length(), 3)
  assert_eq(rows[0].get("users.name"), Some(Value::text("alice")))
  assert_eq(rows[0].get("orders.item"), Some(Value::text("book")))
  assert_eq(rows[1].get("users.name"), Some(Value::text("alice")))
  assert_eq(rows[1].get("orders.item"), Some(Value::text("pen")))
  assert_eq(rows[2].get("users.name"), Some(Value::text("bob")))
  assert_eq(rows[2].get("orders.item"), Some(Value::text("cup")))
}

///|
test "memory left join keeps unmatched left rows" {
  let db = Memory::new()
  try! db.create_table("users", ["id", "name"])
  try! db.create_table("orders", ["id", "user_id", "item"])
  let uid : Column[Int] = Column::new("users", "id")
  let uname : Column[String] = Column::new("users", "name")
  let oid : Column[Int] = Column::new("orders", "id")
  let ouid : Column[Int] = Column::new("orders", "user_id")
  let item : Column[String] = Column::new("orders", "item")

  let _ = try! db.insert(Insert::into("users").set(uid.set(1)).set(uname.set("alice")))
  let _ = try! db.insert(Insert::into("users").set(uid.set(2)).set(uname.set("bob")))
  let _ = try! db.insert(
    Insert::into("orders").set(oid.set(100)).set(ouid.set(1)).set(item.set("book")),
  )

  let rows = try! db.select(
    Select::from("users").left_join("orders", ouid.eq_col(uid)),
  )
  assert_eq(rows.length(), 2)
  // alice matches order 100.
  assert_eq(rows[0].get("users.name"), Some(Value::Text("alice")))
  assert_eq(rows[0].get("orders.item"), Some(Value::Text("book")))
  // bob has no order: right-hand columns are null.
  assert_eq(rows[1].get("users.name"), Some(Value::Text("bob")))
  assert_eq(rows[1].get("orders.id"), Some(Value::Null))
  assert_eq(rows[1].get("orders.item"), Some(Value::Null))
}

///|
test "memory right join keeps unmatched right rows" {
  let db = Memory::new()
  try! db.create_table("users", ["id", "name"])
  try! db.create_table("orders", ["id", "user_id", "item"])
  let uid : Column[Int] = Column::new("users", "id")
  let uname : Column[String] = Column::new("users", "name")
  let oid : Column[Int] = Column::new("orders", "id")
  let ouid : Column[Int] = Column::new("orders", "user_id")
  let item : Column[String] = Column::new("orders", "item")

  let _ = try! db.insert(Insert::into("users").set(uid.set(1)).set(uname.set("alice")))
  let _ = try! db.insert(
    Insert::into("orders").set(oid.set(100)).set(ouid.set(1)).set(item.set("book")),
  )
  let _ = try! db.insert(
    Insert::into("orders").set(oid.set(101)).set(ouid.set(2)).set(item.set("cup")),
  )

  let rows = try! db.select(
    Select::from("users").right_join("orders", ouid.eq_col(uid)),
  )
  assert_eq(rows.length(), 2)
  // order 100 matches alice.
  assert_eq(rows[0].get("users.name"), Some(Value::Text("alice")))
  assert_eq(rows[0].get("orders.item"), Some(Value::Text("book")))
  // order 101 has no user: left-hand columns are null.
  assert_eq(rows[1].get("users.id"), Some(Value::Null))
  assert_eq(rows[1].get("orders.item"), Some(Value::Text("cup")))
}

///|
test "memory full join keeps unmatched rows on both sides" {
  let db = Memory::new()
  try! db.create_table("users", ["id", "name"])
  try! db.create_table("orders", ["id", "user_id", "item"])
  let uid : Column[Int] = Column::new("users", "id")
  let uname : Column[String] = Column::new("users", "name")
  let oid : Column[Int] = Column::new("orders", "id")
  let ouid : Column[Int] = Column::new("orders", "user_id")
  let item : Column[String] = Column::new("orders", "item")

  let _ = try! db.insert(Insert::into("users").set(uid.set(1)).set(uname.set("alice")))
  let _ = try! db.insert(Insert::into("users").set(uid.set(2)).set(uname.set("bob")))
  let _ = try! db.insert(
    Insert::into("orders").set(oid.set(100)).set(ouid.set(1)).set(item.set("book")),
  )
  let _ = try! db.insert(
    Insert::into("orders").set(oid.set(101)).set(ouid.set(3)).set(item.set("cup")),
  )

  let rows = try! db.select(
    Select::from("users").full_join("orders", ouid.eq_col(uid)),
  )
  assert_eq(rows.length(), 3)
  // matched pair.
  assert_eq(rows[0].get("users.name"), Some(Value::Text("alice")))
  assert_eq(rows[0].get("orders.item"), Some(Value::Text("book")))
  // bob has no order.
  assert_eq(rows[1].get("users.name"), Some(Value::Text("bob")))
  assert_eq(rows[1].get("orders.id"), Some(Value::Null))
  // order 101 has no user.
  assert_eq(rows[2].get("users.id"), Some(Value::Null))
  assert_eq(rows[2].get("orders.item"), Some(Value::Text("cup")))
}

///|
test "memory group by sum with having" {
  let db = Memory::new()
  try! db.create_table("t", ["city", "score"])
  let city : Column[String] = Column::new("t", "city")
  let score : Column[Int] = Column::new("t", "score")
  let _ = try! db.insert(
    Insert::into("t").set(city.set("SF")).set(score.set(1)),
  )
  let _ = try! db.insert(
    Insert::into("t").set(city.set("SF")).set(score.set(2)),
  )
  let _ = try! db.insert(
    Insert::into("t").set(city.set("NY")).set(score.set(10)),
  )
  let _ = try! db.insert(
    Insert::into("t").set(city.set("NY")).set(score.set(20)),
  )

  let groups = try! db.select(
    Select::from("t").group_by(city).sum(score).having(city.eq("NY")),
  )
  assert_eq(groups.length(), 1)
  assert_eq(groups[0].get("city"), Some(Value::text("NY")))
  assert_eq(groups[0].get("sum"), Some(Value::int(30)))
}
