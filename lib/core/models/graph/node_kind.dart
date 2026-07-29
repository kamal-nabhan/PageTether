/// Every kind of visual element a [GraphNode] can be.
///
/// Defined in full up front (see the framework-pivot design note this graph
/// is built against) even though only a handful of these are actually
/// produced before the canvas UI phase — [GraphNode.fromJson] must already
/// be able to round-trip whatever kind a later phase starts writing, and a
/// sync payload from a newer app version may contain a kind this build
/// doesn't create yet.
enum NodeKind {
  /// A highlighted passage lifted from a book page.
  highlight,

  /// An underlined passage lifted from a book page.
  underline,

  /// A free-floating (or anchored) plain-text note.
  textNote,

  /// A hand-drawn freehand stroke (see `VectorNodeContent`).
  ink,

  /// A drawn geometric shape (rectangle/ellipse/arrow-as-shape/etc.).
  shape,

  /// An embedded image (see `ImageNodeContent`).
  image,

  /// An AI-generated summary card, typically synthesized from one or more
  /// other nodes rather than anchored to a single passage.
  aiSummary,

  /// A link/jump to another [Board] or location, rendered as a portal-style
  /// node on the canvas.
  portal,

  /// A small status/label chip (see [GraphNode.badge]).
  badge,

  /// A card rendering a whole book page (not just an excerpt).
  pdfPageCard,

  /// An arbitrary clipped region of a page not aligned to text (e.g. a
  /// figure or diagram lifted out via a freeform selection).
  regionClip,
}
