# Family Tasks App Store Release Checklist

## Xcode Signing

- Set the app target's Team to your Apple Developer account.
- Confirm the bundle identifier is registered: `com.naveenkeerthy.FamilyTasks`.
- Confirm the iCloud container is registered and assigned to the app: `iCloud.com.naveenkeerthy.FamilyTasks`.
- Enable CloudKit and Push Notifications for the App ID in Apple Developer.
- Create or refresh provisioning profiles after enabling capabilities.

## App Store Connect

- Create the app record with the bundle identifier `com.naveenkeerthy.FamilyTasks`.
- Category: Productivity.
- Version: `1.0`.
- Upload screenshots for every supported device class.
- Add app description, keywords, support URL, marketing URL if available, and copyright.

## Privacy

- Declare calendar access because the app writes scheduled tasks to the user's calendar.
- Declare photo library access because profile photos can be selected.
- Declare iCloud/CloudKit use when family sharing sync is connected to production data.
- If analytics, crash reporting, or third-party SDKs are added later, update the App Privacy answers before submission.

## Functional Review

- Test first launch, adding tasks, editing tasks, calendar sync, profile settings, and member email validation on a physical device.
- Test iCloud/CloudKit sharing with at least two Apple IDs before App Review.
- Verify the app behaves gracefully when calendar permission is denied.
- Verify the app behaves gracefully when iCloud is disabled or unavailable.

## Archive

- Select `Any iOS Device`.
- Product > Archive.
- Validate the archive in Organizer.
- Distribute App > App Store Connect.
