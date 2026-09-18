# MoonORM

A typed, injection-safe SQL query builder for MoonBit, with a pluggable
connection boundary and a dependency-free in-memory backend.

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
- `query.mbt` — `Select` / `Insert` / `Update` / `Delete` builders and `Statement`.
- `conn.mbt` — `Row`, `ExecResult`, and the `Connection` trait.
- `memory.mbt` — an in-memory `Connection` implementation (no FFI, no deps).
- `error.mbt` — `OrmError`.

## Running

```sh
moon test          # 21 tests: SQL rendering, error cases, in-memory CRUD
moon run cmd/main  # end-to-end demo: build → execute → rows
```

There are no external dependencies beyond the MoonBit core library. The in-memory
backend runs on the wasm-gc target, so the demo needs no database and no C
compiler.

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

## The `Connection` boundary

Builders hand structured queries to a backend, not SQL strings. A SQL driver
renders with `build()` and binds parameters; the in-memory backend evaluates the
structure directly. The trait is the replaceable boundary — same call sites,
different backend:

```moonbit nocheck
///|
pub trait Connection {
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

- Single-table queries. No `JOIN`, no subqueries, no `GROUP BY`.
- One backend (`Memory`). A SQLite or Postgres driver is the natural next step;
  it would implement `Connection` by calling `build()` and binding `params`.
- `Condition::raw` works for SQL rendering but is rejected by `Memory`.

## License

Apache-2.0.
