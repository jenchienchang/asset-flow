# Security

AssetFlow offers an optional app lock that covers its main and Settings windows until you authenticate. App lock does not encrypt stored records or exported backups.

## Enabling App Lock

1. Open **Settings** (++cmd+comma++) and go to the **Security** section.
1. Toggle **Require Authentication** on.

![Security settings](../../assets/images/settings-security.png)

## Authentication Methods

AssetFlow asks macOS to authenticate you using its [device-owner authentication policy](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication). Depending on your Mac and its settings, the system may offer Touch ID, a nearby paired Apple Watch, or your Mac login password. macOS chooses the available methods; AssetFlow does not set their order. If authentication fails or you cancel it, the app stays locked.

## Timeout Settings

Control when AssetFlow locks itself with two independent timeout settings:

### When Switching Apps

How quickly the app locks after you switch away (e.g., ++cmd+tab++ to another app).

| Option          | Behavior                             |
| --------------- | ------------------------------------ |
| **Immediately** | Locks the moment you leave AssetFlow |
| **1 Min**       | Locks after 1 minute away            |
| **5 Min**       | Locks after 5 minutes away           |
| **15 Min**      | Locks after 15 minutes away          |
| **Never**       | Does not lock for app switching      |

### When Locked or Sleeping

How quickly the app locks when your Mac's screen locks or enters sleep mode.

| Option          | Behavior                                    |
| --------------- | ------------------------------------------- |
| **Immediately** | Locks as soon as the screen locks or sleeps |
| **1 Min**       | Locks after 1 minute of screen lock/sleep   |
| **5 Min**       | Locks after 5 minutes of screen lock/sleep  |
| **15 Min**      | Locks after 15 minutes of screen lock/sleep |
| **Never**       | Does not lock for screen lock or sleep      |

Setting both timeouts to **Never** turns off Require Authentication and unlocks the app. If you enable app lock again, both timeouts reset to **Immediately**.

!!! tip

    Set "When Switching Apps" to "Never" if you frequently switch between AssetFlow and a spreadsheet while updating values.

## Lock Screen

When locked, an overlay covers the app's main and Settings windows. To unlock:

1. Click **Unlock** on the lock screen.
1. Complete the authentication prompt using a method offered by macOS.

The app can open the authentication prompt automatically when it becomes active. If you cancel or fail an attempt, use **Unlock** to try again.

![Lock screen](../../assets/images/lock-screen.png)

!!! note

    When the app is locked, tooltips and hover effects are also hidden to prevent data leakage through the lock overlay.

## See also

- [Preferences](preferences.md): Customize display and import settings
- [Backup & Restore](backup-restore.md): Protect your data with regular backups
