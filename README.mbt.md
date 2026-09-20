# MoonORM

[![CI](https://github.com/Rz-coder8848/moonorm/actions/workflows/ci.yml/badge.svg)](https://github.com/Rz-coder8848/moonorm/actions)
[mooncakes.io](https://mooncakes.io/packages/Rz-coder8848/moonorm)

A typed, injection-safe SQL query builder for MoonBit, with a pluggable
connection boundary and two backends: a dependency-free in-memory store and a
native SQLite driver.

SQL is built through a small DSL of typed columns instead of string
concatenation. Every value is bound as a positional parameter, so there is no
path for SQL injection through user input. The builder renders to a
`Statement { sql, params }` pair that any SQL driver can execute.

```moonbit nocheck
///|
let age : Column[Int] = Column::new("users", "age")

///|
let stmt = Select::from("users")
  .where_(age.gte(18))
  .order_by(age.desc())
  .limit(10)
  .build()
// stmt.to_sql()    == SELECT * FROM "users" WHERE "users"."age" >= ? ORDER BY "users"."age" DESC LIMIT 10
// stmt.to_params() == [Value::int(18)]
```

## What's here

- `ast.mbt` — the DSL: `Column`, `Condition`, `Order`, `Assignment`.
- `query.mbt` — `Select` / `Insert` / `Update` / `Delete` builders and `Statement`,
  plus aggregates (`COUNT` / `SUM` / `AVG` / `MIN` / `MAX`), `GROUP BY` / `HAVING`,
  `INNER` / `LEFT` / `RIGHT` / `FULL JOIN`, and subqueries (`IN` / `EXISTS`,
  scalar comparison, and correlated).
- `conn.mbt` — `Row`, `ExecResult`, and the `Connection` / `Transactional` traits.
- `memory.mbt` — an in-memory `Connection` implementation (no FFI, no deps).
- `error.mbt` — `OrmError`.
- `sqlite/` — a native SQLite `Connection` over a vendored SQLite amalgamation.
- `cmd/main` / `cmd/sqlite_demo` — runnable demos of the same builders against
  the in-memory backend and against SQLite.

## Running

```sh
moon test                    # 48 tests on wasm-gc: SQL rendering, errors, CRUD, joins, subqueries
moon test --target native    # + 3 SQLite tests (CRUD, null/float, transactions)
moon run cmd/main            # in-memory demo: build -> execute -> rows
moon run cmd/sqlite_demo --target native  # the same demo against SQLite
```

The core library has no external dependencies beyond the MoonBit core library.
The in-memory backend runs on the wasm-gc target, so the demo needs no database
and no C compiler. The SQLite driver targets the native backend, needs a C
toolchain, and vendors the SQLite amalgamation so there is no system `sqlite3`
to install.

## The DSL

Columns carry a compile-time type so comparisons stay type-checked:

```moonbit nocheck
///|
let id : Column[Int] = Column::new("users", "id")

///|
let email : Column[String] = Column::new("users", "email")

// where id = 1 AND (email LIKE '%@example.com' OR email IS NULL)

///|
let cond = id.eq(1).and_(email.like("%@example.com").or_(email.is_null()))
```

Conditions combine with `and_` / `or_` / `not_` (the bare `and` / `or` / `not`
are MoonBit keywords). `Condition::raw(sql)` is an escape hatch for operators
the DSL doesn't model; the in-memory backend rejects it.

Aggregation and joins are first-class too:

```moonbit nocheck
///|
let stmt = Select::from("orders")
  .group_by(Column::new("orders", "status"))
  .count()
  .build()
// SELECT "orders"."status", COUNT(*) FROM "orders" GROUP BY "orders"."status"
```

```moonbit nocheck
///|
let user_id : Column[Int] = Column::new("orders", "user_id")

///|
let stmt = Select::from("orders")
  .left_join("users", user_id.eq(Column::new("users", "id")))
  .build()
// SELECT * FROM "orders" LEFT JOIN "users" ON "orders"."user_id" = "users"."id"
// `.join` is the inner join; `.left_join`, `.right_join`, and `.full_join`
// are the outer joins.
```

Subqueries plug into `WHERE`. They may reference the outer query's columns —
a correlated subquery — or be compared to a single value (a scalar subquery):

```moonbit nocheck
///|
let user_id : Column[Int] = Column::new("orders", "user_id")

///|
let stmt = Select::from("users")
  .where_(
    Column::new("users", "id").in_select(
      Select::from("orders").columns([user_id.to_ref()]),
    ),
  )
  .build()
// SELECT * FROM "users" WHERE "users"."id" IN (SELECT "orders"."user_id" FROM "orders")
// `Condition::exists(sub)` gives EXISTS; wrap in `.not_()` for NOT EXISTS.
```

```moonbit nocheck
///|
let uid : Column[Int] = Column::new("users", "id")

///|
let ouid : Column[Int] = Column::new("orders", "user_id")

///|
let stmt = Select::from("users")
  .where_(Condition::exists(Select::from("orders").where_(ouid.eq_col(uid))))
  .build()
// SELECT * FROM "users" WHERE EXISTS (SELECT * FROM "orders" WHERE "orders"."user_id" = "users"."id")

///|
let age : Column[Int] = Column::new("users", "age")
// users whose age is above the average:

///|
let stmt2 = Select::from("users")
  .where_(age.gt_sub(Select::from("users").avg(age)))
  .build()
// SELECT * FROM "users" WHERE "users"."age" > (SELECT AVG("users"."age") FROM "users")
```

## The `Connection` boundary

Builders hand structured queries to a backend, not SQL strings. A SQL driver
renders with `build()` and binds parameters; the in-memory backend evaluates the
structure directly. The trait is the replaceable boundary — same call sites,
different backend:

```moonbit nocheck
///|
pub(open) trait Connection {
  fn select(Self, Select) -> Array[Row] raise OrmError
  fn insert(Self, Insert) -> ExecResult raise OrmError
  fn update(Self, Update) -> ExecResult raise OrmError
  fn delete(Self, Delete) -> ExecResult raise OrmError
}
```

`Memory` implements it:

```moonbit nocheck
let db = Memory::new()
db.create_table("users", ["id", "name", "age"])

db.insert(Insert::into("users").set(id.set(1)).set(name.set("alice")).set(age.set(30)))

let rows = db.select(Select::from("users").where_(age.gte(18)))
```

`Sqlite` (native target) implements the same trait:

```moonbit nocheck
let db = Sqlite::open(":memory:")
db.exec("CREATE TABLE users (id INTEGER, name TEXT, age INTEGER)")

db.insert(Insert::into("users").set(id.set(1)).set(name.set("alice")).set(age.set(30)))

let rows = db.select(Select::from("users").where_(age.gte(18)))
```

Transactions are an optional capability, not part of `Connection`. A backend
implements `Transactional` only if it can run multi-statement transactions:

```moonbit nocheck
///|
pub(open) trait Transactional {
  fn begin(Self) -> Unit raise OrmError
  fn commit(Self) -> Unit raise OrmError
  fn rollback(Self) -> Unit raise OrmError
}
```

`Sqlite` implements it (`BEGIN` / `COMMIT` / `ROLLBACK`); `Memory` does not. The
two demos show the boundary side by side: `cmd/main` runs on `Memory`, while
`cmd/sqlite_demo` runs the same builders on `Sqlite` and wraps seeding in a
transaction.

## Design notes

- **Parameterized SQL.** Values are never interpolated into the text. The
  builder emits `?` placeholders and a parallel `params` array.
- **Phantom type columns.** `Column[T]`'s type parameter never appears in the
  SQL; it exists only so `Column[Int]::eq` takes an `Int`. This is a
  compile-time marker, not a runtime value.
- **No string SQL in the hot path.** `Connection` takes the builder types, so
  an in-memory backend doesn't have to parse SQL back.
- **Value smart constructors.** Enum variants are read-only outside the package
  (a MoonBit interface rule), so construct results with `Value::int(1)`,
  `Value::text("x")`, etc.

## Limits

- One join per `SELECT` (`INNER` / `LEFT` / `RIGHT` / `FULL`); the in-memory
  backend evaluates all four join kinds, padding the missing side with nulls.
- Subqueries support `IN`, `EXISTS`, and scalar comparison, and may be
  correlated — they can reference the outer row. Correlation is single-level:
  a subquery sees its immediate outer query's columns, not a grand-outer.
- Transactions are opt-in via `Transactional`: `Sqlite` implements it, `Memory`
  does not.
- `Condition::raw` works for SQL rendering but is rejected by `Memory`.
- The SQLite driver is native-only (not available on wasm-gc).

## License

Apache-2.0.

The native backend vendors the SQLite amalgamation (`sqlite/sqlite3.c` and
`sqlite3.h`, version 3.53.4). SQLite is in the public domain, so it carries no
license terms and imposes no restrictions on use or redistribution.
