// Durations, counted the way an OTLP histogram point counts them.

///|
/// The explicit bounds an OTLP histogram of seconds uses when nothing else is given: the SDK's own
/// defaults, five milliseconds to ten seconds, in seconds. A turn that takes longer than the last
/// bound lands in the overflow bucket, which every histogram has.
let second_bounds : Array[Double] = [
  0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0,
]

///|
/// A cumulative histogram of seconds.
///
/// The conventions name one duration per operation, and one operation is one observation, so the
/// aggregation an OTLP histogram point asks for is four numbers and a row of buckets. There is no
/// meter in this stack to keep them, so this keeps them: the counts never reset, because what is
/// exported is the state of the world rather than the difference since last time.
priv struct Seconds {
  bounds : Array[Double]
  counts : Array[Int64]
  mut total : Double
  mut count : Int64
  mut least : Double
  mut most : Double
  mut since : Int64
}

///|
fn Seconds::new() -> Seconds {
  {
    bounds: second_bounds,
    counts: Array::make(second_bounds.length() + 1, 0L),
    total: 0.0,
    count: 0L,
    least: 0.0,
    most: 0.0,
    since: 0L,
  }
}

///|
/// Adds one measurement. A value equal to a bound counts in the bucket that bound closes, which is
/// what a reader of `(previous, bound]` expects.
fn Seconds::observe(self : Seconds, seconds : Double, at : Int64) -> Unit {
  if self.count == 0L {
    self.since = at
    self.least = seconds
    self.most = seconds
  } else {
    if seconds < self.least {
      self.least = seconds
    }
    if seconds > self.most {
      self.most = seconds
    }
  }
  let mut bucket = 0
  let mut index = 0
  while index < self.bounds.length() {
    if seconds <= self.bounds[index] {
      break
    }
    bucket = bucket + 1
    index = index + 1
  }
  self.counts[bucket] = self.counts[bucket] + 1L
  self.total = self.total + seconds
  self.count = self.count + 1L
}

///|
/// What has been counted so far, as the point an OTLP histogram carries: the bounds, one count per
/// bucket plus the overflow, the sum, and the extremes.
fn Seconds::point(
  self : Seconds,
  attributes : Array[(String, @trace.Value)],
) -> @otlp.DataPoint {
  {
    attributes,
    start: Some(self.since),
    time: now(),
    point: @otlp.Point::Buckets(
      bounds=self.bounds,
      counts=self.counts.copy(),
      sum=self.total,
      count=self.count,
      min=Some(self.least),
      max=Some(self.most),
    ),
    exemplars: [],
    flags: 0,
  }
}

///|
/// How long two readings of the clock are between them, in the seconds a duration is measured in.
fn seconds_between(started : Int64, ended : Int64) -> Double {
  let elapsed = if ended > started { ended - started } else { 0L }
  elapsed.to_double() / 1_000_000_000.0
}
