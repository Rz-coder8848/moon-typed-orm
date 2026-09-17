///|
/// Errors raised while building or running queries.
pub suberror OrmError {
  InvalidIdentifier(String)
  InvalidQuery(String)
  Backend(String)
}

///|
/// Smart constructor for backend errors. Like [`Value`], `OrmError`'s variants
/// are read-only outside this package; drivers raise backend failures through
/// this instead of building the variant directly.
pub fn OrmError::backend(why : String) -> OrmError {
  OrmError::Backend(why)
}

///|
/// Human-readable message, used for error reporting.
pub fn OrmError::message(self : OrmError) -> String {
  match self {
    OrmError::InvalidIdentifier(name) => "invalid identifier: \{name}"
    OrmError::InvalidQuery(why) => "invalid query: \{why}"
    OrmError::Backend(why) => "backend error: \{why}"
  }
}
