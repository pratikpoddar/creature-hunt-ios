# Creature Hunt for Meta glasses (iPhone app)

Find invisible creatures by sound, then turn your head to face them. The iPhone runs the game;
Meta glasses supply head tracking and play the sound through their open-ear speakers.

## What's in this version

- **Three ways to turn:** Meta glasses head tracking, the phone's own motion, or touch (arrows / drag).
- **3D audio:** each creature is placed around you with HRTF rendering. Calls behind you sound muffled.
  A tone rises while you're locked on.
- **“Hey Meta, start Creature Hunt”** launches a hunt hands-free.
- **Meta Ray-Ban Display support:** the lens shows the start screen, “Listen…” / “Hold steady…”
  while hunting, each catch with its illustration, and your result. Buttons in the lens
  (Start hunting, Hint, Hunt again) work with the Neural Band. It never shows where a creature
  is: the game is still played by ear.
- **Simulated glasses** (debug builds) so you can try the glasses flow in the Simulator.
- The same five-creature hunt, difficulty ladder, hints and best time as the web prototype.
  All sounds are generated in code.

## Requirements

- A Mac with Xcode 26.4 or later (needed by Meta's toolkit 1.0.x)
- An iPhone on iOS 17.2 or later, with the **Meta AI** app installed
- Ray-Ban Meta, Oakley Meta or Meta Ray-Ban Display glasses (optional — see “Without glasses”)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build and run

1. In this folder, run `xcodegen generate`, then open `CreatureHunt.xcodeproj`.
   Xcode downloads Meta's toolkit (`meta-wearables-dat-ios` 1.0.1) automatically.
2. Select the **CreatureHunt** target → Signing & Capabilities → choose your Team.
   A free Apple ID works (it appears as "Personal Team"). The bundle ID is
   `com.pratikpoddar.creaturehunt`; leave it unless that ID is already taken on your team.
3. On the iPhone: Settings → Privacy & Security → **Developer Mode** on. Plug it in and press **Run**.
   On first launch, trust the developer under Settings → General → VPN & Device Management.

With a free Apple ID the installed app stops opening after 7 days; press Run again to renew.
TestFlight and the App Store need the paid Apple Developer Program.

### Meta and Apple IDs (not committed)

`Info.plist` reads `MetaAppID` and `ClientToken` from the build settings `META_APP_ID` and
`CLIENT_TOKEN`, set in `Config/Base.xcconfig` (placeholders `0`). To use real values, copy
`Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` (git-ignored) and fill in the
values from Wearables Developer Center and your Apple team ID. Re-run `xcodegen generate`.

## Connect your glasses

1. In the **Meta AI** app: Settings → your glasses → turn on **Developer Mode**.
2. In **Wearables Developer Center**, create an app for this bundle identifier and enable
   **Motion** and **Voice Invocations** (both are experimental capabilities).
   Set the spoken app name to “Creature Hunt”.
3. In Creature Hunt, choose **Glasses** under the ring, tap **Connect glasses**, and approve it
   in Meta AI. You'll be sent back to the game.
4. Put the glasses on. The lantern should follow your head.
   If turning right moves the lantern left, switch on **Reverse turn direction**.

With Developer Mode on, `MetaAppID` and `ClientToken` can stay `0`.
For testers on a release channel, put the real values in `Config/Secrets.xcconfig` (see above).

## Without glasses

- **Phone:** choose **Phone**, wear headphones, hold the phone upright and turn your body.
- **Touch:** choose **Touch** and use the arrows or drag the ring.
- **Simulated glasses:** in a debug build, choose **Glasses → Simulate**.
  *Ray-Ban Meta* pairs a fake pair whose head turns slowly to the right.
  *Meta Ray-Ban Display* does the same and shows the lens screen inside the app, so you can
  check the Display screens without the glasses.

## How head tracking works

`Heading/YawIntegrator.swift` takes the glasses' accelerometer (which way is up) and gyroscope
(how fast the head spins around that up axis) and integrates them into a heading. It doesn't
depend on how the glasses define their axes, so it works the same for the glasses and the phone.
It drifts slowly over minutes, which doesn't matter here because the game only cares about where
sounds are relative to you.

## Project layout

| Folder | What's there |
| --- | --- |
| `App` | App entry, URL callback from Meta AI |
| `Game` | Game engine, creatures, difficulty |
| `Audio` | 3D audio engine and sound synthesis |
| `Heading` | Head/phone heading from motion sensors |
| `Glasses` | Meta toolkit: registration, session, motion, display screens (`GlassesHUD.swift`), voice launch, simulated glasses |
| `UI` | SwiftUI screens and theme |

## Known limits

- **Builds clean.** GitHub Actions (Xcode 26.6) has built Debug for the simulator and Release
  for a device with zero errors since 2026-10-27. Not yet tested on real glasses.
- **No public App Store release yet.** Meta doesn't allow Device Access Toolkit apps on the
  App Store yet; the ceiling today is TestFlight plus Meta's invite-only release channels.
- **Display updates are deliberately rare.** Each update is sent over the air and replaces the
  whole lens screen, so the game only sends one when something meaningful changes, not every frame.
- **Motion and Voice Invocations are experimental** in Meta's toolkit. They work in development
  and for beta testers on your release channels, but apps using them can't be published to the
  public yet.
- **Open-ear speakers** give weaker direction cues than headphones. Test whether you can still
  tell left from right and front from back on real glasses; if not, widen the catch angle in
  `Game/Creature.swift`.

## Changes in 1.0 (Hark review)

- Checked every Meta toolkit call against the 1.0.1 SDK interfaces (Core, Motion, Display, MockDevice): signatures match.
- Bundle ID set to `com.pratikpoddar.creaturehunt`, version 1.0.
- "Reverse turn direction" is now remembered between launches.
- New "Wider catch angle" switch (1.6x) for open-ear glasses speakers, remembered between launches.
- Added `PrivacyInfo.xcprivacy` (UserDefaults, reason CA92.1) and `ITSAppUsesNonExemptEncryption = NO`, both needed for App Store / TestFlight upload.
- Added a GitHub Actions workflow (`.github/workflows/build.yml`) that builds Debug-simulator and Release-device on a macOS runner and publishes errors to the `ci-logs` branch.
- Meta App ID, client token and Apple team now come from `Config/*.xcconfig` instead of being hard-coded; real values live in a git-ignored `Config/Secrets.xcconfig`.

## Developer

Tinkerer (Pratik Poddar), 76, Vrindavan Vihar, Ajmer Road, Jaipur, Rajasthan 302019, India.
