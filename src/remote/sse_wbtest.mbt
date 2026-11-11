// Reading a feed: where an event ends, and what it says.

///|
test "an event ends at the blank line, and the bytes after it start the next one" {
  let buffer = @utf8.encode("data: one\r\n\r\ndata: two\r\n\r\n")
  let (at, width) = event_end(buffer).unwrap()
  assert_eq(at, 9)
  assert_eq(width, 4)
  assert_eq(event_text(buffer.exact_view(start=0, end=at)), Some("one"))
  assert_eq(event_text(buffer.exact_view(start=at + width)), Some("two"))
}

///|
test "a server that writes bare newlines is read the same way" {
  let buffer = @utf8.encode("data: one\n\n")
  let (at, width) = event_end(buffer).unwrap()
  assert_eq(at, 9)
  assert_eq(width, 2)
  assert_eq(event_text(buffer.exact_view(start=0, end=at)), Some("one"))
}

///|
test "an event cut in half has no end yet" {
  assert_true(event_end(@utf8.encode("data: one\r\n")) is None)
  assert_true(event_end(@utf8.encode("data: one")) is None)
  assert_true(event_end(Bytes::new(0)) is None)
}

///|
test "an event with no data is a keepalive, not a message" {
  let frame = @utf8.encode(": keepalive")
  assert_true(event_text(frame) is None)
  assert_true(event_text(@utf8.encode(": one\r\n: two")) is None)
}

///|
test "a message spread over several data lines arrives joined" {
  let frame = @utf8.encode("data: {\"id\":1,\r\ndata: \"result\":2}\r\n")
  assert_eq(event_text(frame), Some("{\"id\":1,\n\"result\":2}"))
}

///|
test "fields the transport does not use are ignored, with the event still read" {
  let frame = @utf8.encode("event: message\r\nid: 7\r\ndata: hello\r\n")
  assert_eq(event_text(frame), Some("hello"))
}

///|
test "a data line with no space after the colon keeps its own first character" {
  assert_eq(event_text(@utf8.encode("data:x")), Some("x"))
  assert_eq(event_text(@utf8.encode("data: x")), Some("x"))
}

///|
test "an empty data line is a message that is the empty string" {
  assert_eq(event_text(@utf8.encode("data:")), Some(""))
}
