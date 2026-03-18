# iOS Test Strategy

## Covered (baseline)
- Auth lifecycle unit tests.
- Rich-text formatter unit tests.

## Planned coverage
- Store unit tests:
  - sessions filter/sort
  - inventory selection/sort
  - message unread/state transitions
- Service tests:
  - API error mapping
  - cached auth refresh/fallback
  - hub frame parsing and event dispatch
- UI smoke tests:
  - auth gate
  - tab navigation
  - basic chat/session/world flows

## Not covered yet
- End-to-end media upload/download on real device.
- Full accessibility automation checks.

## How to run tests
- Open `ReCon.xcodeproj` in Xcode 16+.
- Run `ReConNativeTests` scheme in simulator.
- CI workflow (to be added) will run simulator unit tests.

## Remaining risk areas
- Websocket reconnect edge cases.
- Inventory/upload workflow parity.
- Notification timing/permission paths.
