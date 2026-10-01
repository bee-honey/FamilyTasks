# CloudKit Sharing Test Plan

Family sharing depends on Apple's CloudKit share flow, so the invite sheet itself must be tested with real iCloud accounts. Use this plan to avoid waiting on App Store releases for every sharing check.

## What Should Sync

- Tasks, including assignees and completion state.
- Family member profile emails used by the app's assignee pickers.
- Shopping shops and shopping items.
- Recurring tasks.
- Meal ideas and planned meals.

## What Should Stay Local

- Calendar access and imported calendar events.
- Notification preferences.
- Profile photo, initials, and display settings.
- Device permissions and local iOS settings.

## Development Testing

1. Install a Debug build from Xcode on two physical devices signed into two different Apple IDs.
2. Confirm the app is using the CloudKit development environment for Debug builds.
3. On the owner device, complete profile setup with a valid email.
4. Open Sync Settings and invite the second Apple ID through iCloud sharing.
5. On the receiver device, tap the invite link and confirm it opens Family Tasks, not just the App Store.
6. If the receiver installs the app from the App Store first, tap the original invite link again.
7. If iOS still routes the link incorrectly, copy the original iCloud invite link, paste it into Sync Settings, and use Accept Invite Link.
8. On the receiver device, accept the invite, open the app, and complete profile setup.
9. Confirm both devices show both profile emails in member lists and assignee pickers.
10. Add or edit one task, recurring task, shopping item, and planned meal on each device.
11. Refresh shared data or relaunch the other device and confirm the data appears.

## Upgrading From the Single-Record Version

Everyone in the family needs this version: phones on older versions stop exchanging changes with updated phones.

1. With both devices on the old version and sharing set up, add a task, a shopping item and a deleted item on each.
2. Update the owner's device and open the app. Confirm nothing is lost, and in CloudKit Console confirm `FamilyItem` records exist and the root record has `schemaVersion = 3` with an empty `payload`.
3. Update the participant's device. Confirm it shows everything, including edits it made while it was still on the old version.
4. Confirm deleted items stay deleted on both devices.

## Push Updates

1. With both devices on this version, leave the participant's app in the background.
2. Add a task assigned to the participant on the owner's device.
3. Within about a minute (silent pushes are not instant and iOS may delay them), the participant should get the "new shared task" notification without opening the app.
4. Repeat with the app force-quit: iOS does not deliver silent pushes to force-quit apps, so the change should arrive the next time the app opens.

## TestFlight Testing

TestFlight builds use the production CloudKit environment. Before submitting to App Review, repeat the same two-device flow with a TestFlight build so the production container, deployed schema, and entitlements are verified.

## CloudKit Console Checks

- Development and production data are separate.
- The production schema must include the `FamilyTaskList` record type (with the `schemaVersion` field) and the `FamilyItem` record type (`kind`, `payload`, `updatedAt`, `updatedBy`). Deploy schema changes from Development to Production before releasing.
- Each task, shop, shopping item, recurring task, meal, idea, member and profile is its own `FamilyItem` record, with the shared `FamilyTaskList` root record as its parent. Health data is one record per member (`health:<email>`), shop order is the `household` record, and deleted items are kept as `kind = deleted` records for 180 days.
- Once migrated, the root record has `schemaVersion = 3` and an empty `payload`. Older app versions stored the whole household in that `payload` field.
- The app's `Info.plist` must include `CKSharingSupported` set to `true`; otherwise, iCloud share links may route users to the App Store instead of opening the app.
- If sharing fails with quota errors, check the owner's iCloud storage before changing app code.
