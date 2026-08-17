/// Returns at most [max] leading items from [items].
///
/// Returns [items] itself when it already fits, so the common case allocates
/// nothing. Used wherever a list crosses a boundary with a documented cap —
/// request candidates, persisted entries, rendered rows — so the cap is applied
/// the same way each time instead of by an open-coded ternary.
List<T> cappedTo<T>(List<T> items, int max) =>
    items.length > max ? items.sublist(0, max) : items;
