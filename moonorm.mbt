///|
/// MoonORM — a typed, injection-safe SQL query builder with a pluggable
/// connection boundary.
///
/// See `README.mbt.md` for a walkthrough. The public surface is split by
/// responsibility:
///
/// * `ast.mbt` — the query DSL: [`Column`], [`Condition`], [`Order`], [`Assignment`]
/// * `query.mbt` — [`Select`], [`Insert`], [`Update`], [`Delete`], [`Statement`]
/// * `conn.mbt` — [`Row`], [`ExecResult`], and the [`Connection`] trait
/// * `memory.mbt` — a dependency-free in-memory [`Connection`] implementation
/// * `error.mbt` — [`OrmError`]
