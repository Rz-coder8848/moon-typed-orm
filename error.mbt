///|
/// Errors raised while building or running queries.
pub suberror OrmError {
  InvalidIdentifier(String)
  InvalidQuery(String)
  Backend(String)
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
