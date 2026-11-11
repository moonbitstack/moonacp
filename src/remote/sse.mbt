// What one server-sent event is: where its bytes end, and the text it carries.
//
// A stream is a sequence of fields, one per line, and a blank line between events. This reads the
// two the transport uses — `data`, and the `:` comment a server sends to keep a connection alive —
// and ignores the rest, which is what a reader of a feed is required to do with fields it does not
// understand.

///|
/// Where the next event's bytes end, and how wide the separator is: two CRLF pairs, or two bare
/// newlines from a server that writes them. The earliest of the two wins.
fn event_end(buffer : Bytes) -> (Int32, Int32)? {
  let crlf = buffer.find(b"\r\n\r\n")
  let lf = buffer.find(b"\n\n")
  match (crlf, lf) {
    (None, None) => None
    (Some(at), None) => Some((at, 4))
    (None, Some(at)) => Some((at, 2))
    (Some(crlf), Some(lf)) =>
      if crlf <= lf {
        Some((crlf, 4))
      } else {
        Some((lf, 2))
      }
  }
}

///|
/// The text one event carries: its `data` lines joined with newlines, or `None` for an event with
/// no data — the keepalive a server sends as a comment.
fn event_text(frame : BytesView) -> String? {
  let text = @utf8.decode_lossy(frame)
  let out = StringBuilder()
  let mut found = false
  for line in text.split("\n") {
    let line = match line.strip_suffix("\r") {
      Some(rest) => rest
      None => line
    }
    guard line.has_prefix("data:") else { continue }
    let rest = line.exact_view(start=5)
    // One space after the colon is part of the field's syntax, not of its value.
    let value = match rest.strip_prefix(" ") {
      Some(value) => value
      None => rest
    }
    if found {
      out.write_string("\n")
    }
    out.write_string(value.to_owned())
    found = true
  }
  if found {
    Some(out.to_string())
  } else {
    None
  }
}
