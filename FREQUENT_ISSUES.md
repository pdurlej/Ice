# Frequent Issues <!-- omit in toc -->

- [Items are moved to the always-hidden section](#items-are-moved-to-the-always-hidden-section)
- [Ice removed an item](#ice-removed-an-item)
- [Ice does not remember the order of items](#ice-does-not-remember-the-order-of-items)
- [How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?](#how-do-i-solve-the-ice-cannot-arrange-menu-bar-items-in-automatically-hidden-menu-bars-error)

## Items are moved to the always-hidden section

By default, macOS adds new items to the far left of the menu bar, which is also the location of Ice's always-hidden section. Most apps are configured
to remember the positions of their items, but some are not. macOS treats the items of these apps as new items each time they appear. This results in
these items appearing in the always-hidden section, even if they have been previously been moved.

Fire can inspect and move individual items through its Layout editor and its
optional MCP integration. It does not automatically restore every item that an
application recreates or that macOS moves. Use Settings → Menu Bar Layout to
place the item again; agent writes remain off unless explicitly enabled.

## Ice removed an item

Fire does not uninstall another app's status item. It may be in the
always-hidden section after macOS recreated or repositioned it. Option + click
the Fire icon to reveal that section, then Command + drag the item into the
desired section, or use Settings → Menu Bar Layout.

## Ice does not remember the order of items

Fire persists the positions of its own section controls. Individual apps and
macOS may recreate their status items with new positions, so order restoration
is not guaranteed for every item.

## How do I solve the `Ice cannot arrange menu bar items in automatically hidden menu bars` error?

1. Open `System Settings` on your Mac
2. Go to `Control Center`
3. Select `Never` as shown in the image below
4. Update your `Menu Bar Items` in `Ice`
5. Return `Automatically hide and show the menu bar` to your preferred settings

![Disable Menu Bar Hiding](https://github.com/user-attachments/assets/74c1fde6-d310-4fe3-9f2b-703d8ccb636a)
