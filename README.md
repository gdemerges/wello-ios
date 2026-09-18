# Wello — Hydration Tracker (iOS)

Personal, single-user, 100% local iOS app. Computes a personalized daily hydration goal
(sex, HealthKit activity, Open-Meteo weather, medical context) and helps you track it —
on iPhone, Apple Watch, and via Home Screen / Lock Screen / Control Center widgets.

## Layout

```
Wello/                          ← root
├─ WelloKit/                    ← Swift Package: pure business logic (CLI-testable)
├─ Wello/                       ← Xcode project
│  ├─ Wello.xcodeproj
│  ├─ Wello/                    ← iPhone app sources (App, Models, Services, Views)
│  ├─ WelloWidget/               ← WidgetKit extension (widgets, Control Widget, Live Activity)
│  ├─ WelloWatch Watch App/     ← watchOS app sources
│  └─ WelloWatchWidget/         ← watchOS complication extension
├─ docs/                        ← design specs and implementation plans
└─ README.md
```

## Getting started

1. Open `Wello/Wello.xcodeproj` in Xcode 27+ (iOS 18+ target).
2. **Link the local package**: File ▸ Add Package Dependencies ▸ Add Local ▸ pick the
   `WelloKit` folder, then add the `WelloKit` library to the `Wello` target.
3. Check that the files under `Wello/Wello/` (App, Models, Services, Views) belong to the
   `Wello` target (with Xcode 16+ synchronized groups this is automatic; otherwise use
   *Add Files to "Wello"*).
4. Configure capabilities & Info.plist (see below).
5. Cmd+R on an iOS 18+ simulator or device.

## Testing the business logic

Critical logic (`HydrationCalculator`, `BiologicalSex`) lives in the `WelloKit` package and
is testable without Xcode:

```bash
cd WelloKit && swift test
```

## Permissions

Enable the **HealthKit** capability on the target (Signing & Capabilities ▸ + Capability ▸
HealthKit), check **Background Delivery**, and set in the target's Info.plist:

- `NSHealthShareUsageDescription` — reading workouts and active energy.
- `NSHealthUpdateUsageDescription` — writing water intake to the Health app.
- `NSLocationWhenInUseUsageDescription` — location for local weather.

Notifications are requested on demand. **Every permission denial is handled**: the app
remains fully usable with manual entry (activity = 0, weather bonus = 0, no reminders).

**Background**: Wello observes workouts and external water intake via `HKObserverQuery` +
background delivery. A finished workout raises the goal, reschedules reminders, and
refreshes the widget, Watch, and Live Activity without the app being open. The wake-up
doesn't query GPS (weather is read from cache): outside the foreground, a location fix is
slow and the wake-up must be acknowledged quickly.

## Erasing your data

Profile ▸ **Privacy**, two distinct actions:

- **Erase my history** — intake, goals, and local caches. The profile survives, today's
  goal is recalculated immediately: no onboarding to redo.
- **Erase everything and start over** — the profile too: the app returns to its first
  launch.

Both offer to also delete the water intake Wello wrote to the Health app (never other
apps' entries: HealthKit forbids it — they're simply flagged so they aren't re-imported).
Wello+ purchases are kept in both cases.

## Calculation logic

```
base          = 2000 ml (male) | 1600 ml (female)        // EFSA fluid intake reference
activity      = min(active energy kcal × 1, 1000)        // 1 ml/kcal (HealthKit), capped
weather       = min(max(0, feels-like°C − 27) × 50, 600)  // apparent temperature, 0 if unavailable
altitude      = min(max(0, alt − 2000)/1000 × 150, 500)   // Open-Meteo, 0 at low elevation/unavailable
build         = clamp(base × 0.5 × (weight−ref)/ref, ±400) // Wello+, ref 70/60 kg; 0 if disabled
physiological = max(0, base + activity + weather + altitude + physioState + renal + build + manual adj.)
total         = min(4000, physiological)                 // sole safeguard: the global cap
```

The base comes from **EFSA (2010) reference intakes**: total water 2.5 L/day (male), 2.0
L/day (female), of which ~80% via beverages → a **2000 ml / 1600 ml** drinking target. We
don't start from body weight (× 35 ml/kg): that coefficient estimates *total* water
(beverages + food + metabolic water) and overestimates the drinking target by ~20-30%.
Personalization happens via sex + activity (kcal) + weather. There is **no floor**: the
EFSA base already serves as one — only settings explicitly chosen by the user (build
adjustment, manual adjustment, both Wello+ and bounded) can lower it. The only safeguard is
the **global 4000 ml cap**, which bounds the total regardless of how the bonuses add up.

The activity bonus derives from **active energy burned** (kcal, HealthKit) rather than
duration alone: sweat loss during exercise is proportional to metabolic heat production.
Evaporating 1 mL of sweat dissipates ~0.58 kcal, and most exercise energy becomes heat →
**~1 mL of water per kcal** (a conservative coefficient, capped at 1000 ml).

The weather bonus relies on **feels-like temperature** (Open-Meteo's apparent
temperature), which already combines heat, humidity, wind, and radiation into one
consistent heat-stress indicator. Linear ramp of **50 mL per °C felt above 27 °C** (comfort
zone), capped at 600 mL. A dry 30 °C (sweat evaporates) and a humid 30 °C (sweat doesn't
evaporate) thus produce very different feels-like readings — and needs.

The **altitude** bonus (Open-Meteo elevation) adds **+150 mL per 1000 m above 2000 m**
(capped at 500 mL): at altitude, dry air and hyperventilation increase fluid loss.

The **build** adjustment (Wello+, opt-in) modulates the EFSA base by body weight: a
fraction **bounded to ±400 mL** of the relative gap to a reference weight (70 kg male / 60
kg female). We do **not** adopt the "35 mL/kg" rule (which estimates *total* water and
overestimates the drinking target) — the build adjustment only *refines* the EFSA
baseline. The full calculation and its sources are exposed in-app via the **"Method"**
screen (every line of the goal breakdown is tappable).

## Where to adjust the goal

**Profile** tab: sex sets the EFSA base; physiological state (pregnancy/breastfeeding) and
renal needs (kidney stones, 500–1500 ml) add their own terms. With **Wello+**, the
"Advanced settings" section unlocks effort/heat sensitivities (×0.5–1.5), manual
adjustment, and build. The 4000 ml cap always applies.

## Architecture

- `WelloKit/` — pure, testable logic (goal calculation, EFSA base by sex, export CSV,
  reminders, streaks/milestones, insights, weekly summary, Watch state reconciliation,
  app themes).
- `Wello/Wello/Models` — SwiftData models (`UserProfile`, `DailyGoal`, `HydrationLog`).
- `Wello/Wello/Services` — HealthKit, weather, location, notifications, StoreKit
  (`EntitlementStore`), theming (`ThemeStore`), Watch sync, Live Activity, `HydrationStore`.
- `Wello/Wello/Views` — SwiftUI screens (Main, History, Analytics, Profile, Paywall,
  Onboarding) + components.

"MV" pattern: no ViewModels; views use SwiftData `@Query` and an `@Observable`
`HydrationStore` injected through the environment. Services sit behind protocols (mocks
provided for previews).

**Today's total — a single aggregate, never recomputed at render time.** `HydrationLog`
entries remain the source of truth, but each `DailyGoal` carries its own total
(`consumedML`, denormalized). `HydrationStore.propagerChangement()` is the single
pass-through point after any mutation: it recomputes today's total (memoized in
`consomméAujourdhui`), writes the column for the affected days, then refreshes the chart
series, widgets, Watch, and Live Activity. Consequences:
- History and Analytics load **no** intake entries to plot their days — their render cost
  no longer depends on account age;
- any write made outside the app must maintain the invariant itself: `AddWaterIntent`
  (widget, Siri, Action Button) updates the day's `DailyGoal` after inserting a log;
- intake `@Query`s stay bounded by predicate (the displayed day, 30 days for analytics);
  only the CSV export loads the full history, on demand.

The `ModelContainer` is a single instance per process (`WelloShared.partagé`): opening it
resolves the App Group, handles migration, and opens SQLite — the widget extension used to
redo this on every timeline.

## Monetization — Wello+

Two StoreKit products, granted by either one being active: an auto-renewable annual
subscription (`com.wello.plus.annual`, 7-day free trial) and a lifetime non-consumable
(`com.wello.plus.lifetime`). `EntitlementStore` exposes a single source of truth
(`isUnlocked(_:)` per feature) consumed by the paywall and gated screens; `Wello.storekit`
mirrors both products for local testing. Wello+ unlocks: unlimited history, CSV export,
advanced goal tuning (build, manual adjustment, effort/heat sensitivities), alternate app
icons and colored themes.

## Themes

Color themes are pure SwiftUI (no manual step). Alternate app icons require the
`AppIcon-*` asset catalogs plus `CFBundleIcons`/`CFBundleAlternateIcons` declared in the
target's Info.plist — see `docs/superpowers/specs/2026-06-18-wello-themes-design.md`.

## Localization

Base language **English**, plus 7 translated languages (fr, es, de, it, pt-BR, ja,
zh-Hans) via `Wello/Wello/Localizable.xcstrings`. SwiftUI literals are
`LocalizedStringKey`s (no `String(localized:)` needed). A key with no translation falls
back to English.

## App Intents / Siri / Shortcuts

`AddWaterIntent` (shared between the app and widget targets) logs an intake entry
silently — no app launch — from the medium widget's quick-add buttons, the Control Widget
(Control Center / Lock Screen), and the Action Button. `WaterAppShortcuts` exposes a
preset 250 ml shortcut to **Siri** and **Spotlight**.

## Accessibility

- **VoiceOver**: the gauge exposes a readable value ("X ml of Y, Z%"); water buttons
  announce "Add N milliliters"; each bar in the history chart carries its date and
  completion rate; decorative icons are hidden from the screen reader.
- **Announcements**: reaching the goal triggers a VoiceOver announcement, in addition to
  the visual banner and haptic feedback.
- **Dynamic Type**: the app uses typography styles that scale; the few fixed display sizes
  (gauge counter, wordmark, onboarding illustrations) follow the system setting via
  `@ScaledMetric`, with a `minimumScaleFactor` fallback to avoid truncation.
- **Reduce Motion**: when the iOS setting is on, the gauge's wave stays drawn but stops
  rippling, level changes become instant, and "spring" animations (celebration, button
  pulse) are neutralized — without taking anything away from other users.
- **Contrast & color**: haptic feedback and text labels duplicate information otherwise
  carried by color alone (goal reached, diagnostic states); a legibility shadow sits under
  water-button text in both light and dark mode. Tap targets ≥ 44 pt.

## Home Screen, Lock Screen & Control Center widgets

Home Screen widgets (small: goal ring; medium: bar + quick-add buttons +150/+250/+500) and
Lock Screen accessories (circular, rectangular, inline), sharing data with the app via the
`group.Life.Wello` App Group (single SwiftData store, migrated from the local store on
first launch). A Control Widget adds a one-tap "+250 ml" button to Control Center and the
Lock Screen. A Live Activity shows the day's progress on the Lock Screen and in the
Dynamic Island while tracking is active.

## Apple Watch app

Standalone Watch app: progress gauge + quick water add on the wrist, usable offline.
**CloudKit-free** sync between the two devices via **WatchConnectivity**: the iPhone
pushes the day's goal/consumed total (coalesced mirror, `updateApplicationContext`); the
Watch queues its own intake entries (`transferUserInfo`, guaranteed delivery) and sends
them to the iPhone, the **sole HealthKit writer** (deduplicated by `watchUUID`, no double
counting). The Watch reads active energy (HealthKit) to raise the goal's "activity" share
mid-workout, even without the iPhone nearby. Consumption reconciliation (`consumed = iPhone
total + unacknowledged local entries`) is pure logic tested in WelloKit
(`ÉtatHydratationWatch`).

**Watch face complication**: a separate WidgetKit watchOS extension (`WelloWatchWidget`)
exposing the `.accessoryCircular` / `.accessoryCorner` / `.accessoryInline` /
`.accessoryRectangular` families. It runs in its own process: the Watch app publishes its
latest `WidgetProgress` to an App Group container **local to the watch**
(`group.Life.Wello`, `WelloWatchShared`) and triggers `WidgetCenter.reloadAllTimelines()`
on every intake entry or sync.

## Scope

No CloudKit anywhere: the app is deliberately local and syncs only iPhone ↔ Watch, device
to device, via WatchConnectivity. There is no server, no account, and no telemetry — see
`Wello/Wello/Services/WelloLog.swift` for the local-only `os.Logger` diagnostics that
replace it.
