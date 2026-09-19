# Getting Started

Welcome to AssetFlow! This page walks you through system requirements, installation, and a quick tour of the app so you know where everything lives.

---

## System Requirements

| Requirement          | Details                                                           |
| -------------------- | ----------------------------------------------------------------- |
| **Operating System** | macOS 15.0 (Sequoia) or later                                     |
| **Architecture**     | Apple silicon or Intel Mac                                        |
| **Disk Space**       | Minimal — AssetFlow stores data locally in a lightweight database |
| **Network**          | Optional — only used to fetch exchange rates                      |

---

## Installation

1. Go to the [Releases](https://github.com/jenchienchang/asset-flow/releases) page on GitHub and download the latest **AssetFlow-x.y.z.zip**.
1. Unzip the file and move **AssetFlow.app** into your **Applications** folder.
1. Launch AssetFlow from **Applications** or Spotlight (++cmd+space++ and type "AssetFlow").

### Bypassing the Gatekeeper Warning

Because AssetFlow is not signed with an Apple Developer certificate, macOS will block it on first launch. This is normal — here's how to allow it:

1. Double-click **AssetFlow.app**. You'll see a warning that the app cannot be opened.
1. Open **System Settings** → **Privacy & Security**.
1. Scroll down to the **Security** section. You'll see a message: *"AssetFlow was blocked from use because it is not from an identified developer."*
1. Click **Open Anyway**, then authenticate with Touch ID or your password.
1. In the confirmation dialog, click **Open**.

The app will open normally on all subsequent launches.

!!! note

    This is a one-time step. Once you've allowed AssetFlow through Gatekeeper, macOS will remember your choice and won't ask again.

---

## First Launch

When you open AssetFlow for the first time, you'll see an empty dashboard with helpful prompts to get started. There's no account to create and no sign-in required — everything runs locally on your Mac.

![Empty dashboard](../../../assets/images/dashboard-empty-state.png)

From here you can:

- **Create your first snapshot** to start tracking your portfolio
- **Import data from a CSV** file if you already have your holdings in a spreadsheet

---

## App Overview

AssetFlow is organized around a sidebar on the left that gives you quick access to every part of the app.

![App overview](../../../assets/images/app-overview.png)

### Sidebar Navigation

The sidebar is divided into three sections:

**Overview**
:   Your main dashboard — a summary of your portfolio with charts and performance metrics.

**Portfolio**
:   - **Snapshots** — browse and manage your portfolio snapshots
    - **Assets** — view and edit all of your tracked assets
    - **Categories** — organize assets into groups and set target allocations
    - **Platforms** — manage the platforms or brokerages where your assets are held

**Tools**
:   - **Rebalancing** — calculate trades needed to reach your target allocation
    - **Import CSV** — bulk import assets or cash flows from spreadsheet files

---

## Next Steps

Ready to add your first data? Head to the **[Quick Start](quick-start.md)** guide to create your first snapshot in just a few minutes.

---

## See also

- [Quick Start](quick-start.md): Step-by-step guide to your first snapshot
- [Dashboard](../guide/dashboard.md): Understanding the overview screen
- [Import CSV](../guide/import-csv.md): Bulk importing data from spreadsheets
