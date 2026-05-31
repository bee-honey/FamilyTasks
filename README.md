# Family Tasks

Family Tasks is a SwiftUI iOS app for running a household together. It combines task planning, calendar-aware today views, shared shopping lists, recurring responsibilities, and meal planning in one family workspace.

## Screenshots

| Menu | Task Matrix |
| --- | --- |
| ![Menu](docs/screenshots/menu.png) | ![Task Matrix](docs/screenshots/matrix.png) |

## Features

- Today view for scheduled tasks and imported calendar events.
- Eisenhower-style task matrix with Do, Schedule, Delegate, and Drop sections.
- Family member assignment using initials/profile avatars.
- Calendar integration with EventKit, including Google calendars configured on the device.
- Shopping lists grouped by shop, with shareable bullet-point lists.
- Recurring tasks for bills, household services, and repeated chores.
- Meal planning with reusable meal ideas, week/day planning, breakfast/lunch/dinner slots, and ingredient-to-grocery handoff.
- Profile/settings area for identity, family members, notifications, and calendar integration.
- App icon, privacy manifest, and App Store release checklist included.

## Project Structure

```text
FamilyTasks/
  Models/       Data models for tasks, shopping, meals, and recurring items
  Stores/       Local persistence and app state
  Services/     Calendar and CloudKit sharing services
  Views/        SwiftUI screens and reusable views
```

## Calendar Sync

The app uses EventKit. If a Google account is added under iOS Settings > Calendar > Accounts, tasks and Today calendar events can use writable Google calendars when available.

## Family Sharing

The app uses CloudKit sharing for a shared household workspace. Tasks, family member emails, shopping lists, recurring tasks, meal ideas, and planned meals are stored as one shared household payload after the owner shares it from Profile > Share Household Data.

CloudKit family sharing should be tested on physical devices with two separate iCloud accounts before App Store submission.

See [`docs/cloudkit-sharing-test-plan.md`](docs/cloudkit-sharing-test-plan.md) for the Debug and TestFlight sharing checklist.

## App Store Notes

See [`FamilyTasks/AppStoreReleaseChecklist.md`](FamilyTasks/AppStoreReleaseChecklist.md) and [`FamilyTasks/AppStoreMetadataDraft.md`](FamilyTasks/AppStoreMetadataDraft.md).

Apple currently requires App Store uploads after April 28, 2026 to be built with the iOS/iPadOS 26 SDK or later, so final archive/upload should be done from Xcode 26+.
