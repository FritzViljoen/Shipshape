# `no-lifecycle-callbacks` — No persistence lifecycle callback, anywhere

No before-save, after-create, after-commit or any of their siblings — in a record, or in
anything included into one.

**A callback hides work behind a save.** The caller reads one method and gets several, in an
order nothing states, with a failure in any of them attributed to the save. Work goes in a
named method the caller invokes, in the operation that wanted it.

It is also the commonest form of action at a distance: the effect is real, and it is not on
the path anyone is reading — see
[`nothing-travels-off-the-call-path`](nothing-travels-off-the-call-path.md).

- **Agreed:** grandfathered — predates this record, and its provenance is the repository's early history rather than a decision anybody can now point at.
- **Principle:** `tell-dont-ask` governs — a callback is the record deciding on the caller's
  behalf. `nothing-is-hidden` also produces it, for the reason above.
- **Guard:** `Shipshape/NoCallbacks`, over the record tree, including concerns mixed into
  one. Fails the registration.
- **Guard's limit:** it sees **registration syntax**. A callback registered dynamically, or
  registered by a gem on your records' behalf, is invisible. Observers and subscribers
  attached outside the record are not covered here — that is
  [`nothing-travels-off-the-call-path`](nothing-travels-off-the-call-path.md), whose list is
  also closed.
