// Failures. What a handler raises goes back as a JSON-RPC error object, so the variants here are
// chosen to name the code the other side will see.

///|
/// The text is not JSON.
pub let parse_error : Int32 = -32700

///|
/// The value is not a valid message.
pub let invalid_request : Int32 = -32600

///|
/// Nobody handles that method.
pub let method_not_found : Int32 = -32601

///|
/// The parameters are not what the method takes.
pub let invalid_params : Int32 = -32602

///|
/// The handler failed for its own reasons.
pub let internal_error : Int32 = -32603

///|
/// The caller asked for the work to stop.
pub let request_cancelled : Int32 = -32800

///|
/// The client has to `authenticate` before this method works.
pub let authentication_required : Int32 = -32000

///|
/// A path, a session or a resource named in the request does not exist.
pub let resource_not_found : Int32 = -32002

///|
/// What a handler raises, and what the other side's error object becomes when a call fails. A
/// variant's code is the JSON-RPC code it travels as: `Refused(code~, ..)` carries the wire code
/// itself, `Unsupported` is -32601, `Malformed` is -32602.
#derive(Eq)
pub(all) suberror Refused {
  Refused(code~ : Int32, message~ : String, data~ : Json?)
  Unsupported(name~ : String)
  Malformed(reason~ : String)
  Closed(reason~ : String)
}

///|
pub extend Refused with Eq::{equal, not_equal}

///|
/// An error object with a code of your choosing.
pub fn Refused::new(code : Int32, message : String, data? : Json) -> Refused {
  Refused(code~, message~, data~)
}

///|
/// The code this failure travels as.
pub fn Refused::code(self : Refused) -> Int32 {
  match self {
    Refused(code~, ..) => code
    Unsupported(_) => method_not_found
    Malformed(_) => invalid_params
    Closed(_) => internal_error
  }
}

///|
/// What the other side reads.
pub fn Refused::message(self : Refused) -> String {
  match self {
    Refused(message~, ..) => message
    Unsupported(name~) => "Method not supported: \{name}"
    Malformed(reason~) => "Invalid params: \{reason}"
    Closed(reason~) => "Closed: \{reason}"
  }
}

///|
/// Anything else attached to the failure.
pub fn Refused::data(self : Refused) -> Json? {
  match self {
    Refused(data~, ..) => data
    Unsupported(_) | Malformed(_) | Closed(_) => None
  }
}

///|
/// The wire form of a failure.
pub fn Refused::failure(self : Refused) -> @moonjrpc.Failure {
  { code: self.code(), message: self.message(), data: self.data(), }
}

///|
/// Turns anything a handler raised into the error object to send: the wire code is kept, and
/// anything that is not a `Refused` becomes -32603 with no detail, because what a handler trips
/// over is not the caller's to read.
pub fn failure_of(error : Error) -> @moonjrpc.Failure {
  match error {
    Refused(..) as refused => refused.failure()
    Unsupported(..) as refused => refused.failure()
    Malformed(..) as refused => refused.failure()
    Closed(..) as refused => refused.failure()
    @moonjrpc.Failed(failure) => failure
    _ => { code: internal_error, message: "Internal error", data: None, }
  }
}

///|
/// The reverse, for a call that came back with an error object.
pub fn refused_of(failure : @moonjrpc.Failure) -> Refused {
  Refused(code=failure.code, message=failure.message, data=failure.data)
}
