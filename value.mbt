///|
/// A single SQL value. Backends translate these onto their own binding types
/// (SQLite `sqlite3_bind_*`, Postgres wire types, etc.).
pub enum Value {
  Null
  Bool(Bool)
  Int(Int)
  Float(Double)
  Text(String)
  Blob(Bytes)
} derive(Eq, @debug.Debug)

///|
/// Smart constructors. The variants are read-only outside this package — they
/// can be matched but not built — so construct values through these.
pub fn Value::null() -> Value {
  Value::Null
}

///|
pub fn Value::bool(b : Bool) -> Value {
  Value::Bool(b)
}

///|
pub fn Value::int(n : Int) -> Value {
  Value::Int(n)
}

///|
pub fn Value::float(f : Double) -> Value {
  Value::Float(f)
}

///|
pub fn Value::text(s : String) -> Value {
  Value::Text(s)
}

///|
pub fn Value::blob(b : Bytes) -> Value {
  Value::Blob(b)
}

///|
/// Types that can be turned into a [`Value`] for query binding.
pub trait ToValue {
  fn to_value(Self) -> Value
}

///|
pub impl ToValue for Value with fn to_value(self) -> Value {
  self
}

///|
pub impl ToValue for Int with fn to_value(self) -> Value {
  Value::Int(self)
}

///|
pub impl ToValue for Double with fn to_value(self) -> Value {
  Value::Float(self)
}

///|
pub impl ToValue for String with fn to_value(self) -> Value {
  Value::Text(self)
}

///|
pub impl ToValue for Bool with fn to_value(self) -> Value {
  Value::Bool(self)
}

///|
pub impl ToValue for Bytes with fn to_value(self) -> Value {
  Value::Blob(self)
}

///|
/// Short type tag, used in error messages when a value mismatches a column.
pub fn Value::type_name(self : Value) -> String {
  match self {
    Null => "null"
    Bool(_) => "bool"
    Int(_) => "int"
    Float(_) => "float"
    Text(_) => "text"
    Blob(_) => "blob"
  }
}
