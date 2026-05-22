# Family Tasks App Store Release

## Build

- App name: Family Tasks
- Bundle ID: com.naveenkeerthy.FamilyTasks
- Version: 1.0
- Build: 1
- Platform: iOS
- Device family for first release: iPhone
- Category: Productivity

## Archive

```sh
xcodebuild -project FamilyTasks.xcodeproj \
  -scheme FamilyTasks \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath ./build/FamilyTasks.xcarchive \
  archive
```

## Upload

Create the app record in App Store Connect first. Then upload the archive from Xcode Organizer, or run:

```sh
xcodebuild -exportArchive \
  -archivePath ./build/FamilyTasks.xcarchive \
  -exportPath ./build/AppStore \
  -exportOptionsPlist ./release/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates
```

## App Store Connect

- Create app record before uploading the first build.
- Primary language: English
- SKU: FamilyTasks
- Bundle ID: com.naveenkeerthy.FamilyTasks
- Availability: choose regions manually during submission.
- Pricing: Free for initial release unless monetization changes.

## Privacy

- Privacy policy URL is required in App Store Connect.
- The current app has no third-party analytics, ads, or tracking SDKs.
- User-created tasks, groceries, meal plans, settings, and shared family data are stored locally and/or in the user's iCloud/CloudKit account for app functionality.
- Calendar access is user-approved and used for displaying/syncing schedule items.
- Photos access is user-approved and used for profile image selection.

## Pre-Submit Checks

- Confirm CloudKit container `iCloud.com.naveenkeerthy.FamilyTasks` is configured for production.
- Confirm App Groups or Push Notifications are not required for the initial release path.
- Capture App Store screenshots on iPhone 6.7-inch and 6.5-inch/6.9-inch class devices.
- Fill App Information, Privacy, Age Rating, Pricing, and Review Information in App Store Connect.
- Upload build, wait for processing, then choose the processed build for TestFlight or App Review.
