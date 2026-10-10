# Build guide (Termux)

## Honest status
- C++ core: compiled and tested here (74 checks, ASan/UBSan clean). Measured tick -> payload ~1 microsecond (excludes network).
- Dart/Flutter code and the Android build: NOT compiled in my sandbox (no Flutter SDK/network). Expect to fix small compile errors on first build. Send me the error text.
- Deriv API usage follows developers.deriv.com (checked Oct 2026): REST https://api.derivws.com, PAT => `Authorization: Bearer` + `Deriv-App-ID`, `POST /trading/v1/options/accounts/{id}/otp` => wss URL, `buy:"1"` + `parameters` (single-step, no proposal).

## Design deviations you should know
1. Network layer is a Dart background isolate, not C++ (TLS WebSocket in C++ needs OpenSSL/Beast, very heavy on Termux). C++ still makes every decision and builds the exact buy JSON.
2. AWS execution service is not included. The same C++ core + Dart worker can run on EC2 later (`dart compile exe`), but one authoritative executor only.
3. Single-step buy (no separate proposal): fewer round trips. `proposal` timestamp is therefore reported as trigger->send.
4. Cold app restart restores the strategy state but PAUSES a running bot (safety). Reconnects inside a session keep it running.
5. OVER 9 / UNDER 0 are rejected (impossible contracts).
6. Spec example "+3.5, +0.5 with trigger digit 3" is impossible under Deviation=Current-Average (digits 0,7,8 give it, trigger digit 8). Formulas were kept as authoritative.

## Path B (recommended, reliable): Termux edits + GitHub Actions compiles
1. `pkg update && pkg install git unzip`
2. `termux-setup-storage`, then `cd ~ && unzip ~/storage/downloads/deriv_bot_kit.zip && cd deriv_bot`
3. Create an empty private repo on github.com, then:
   `git init && git add . && git commit -m init && git branch -M main`
   `git remote add origin https://github.com/YOU/deriv_bot.git && git push -u origin main`
   (use a GitHub personal access token as the password)
4. GitHub -> Actions -> "Build APK" -> wait ~8 min -> download artifact `deriv-bot-apk`, unzip, install app-release.apk.

## Path A (experimental): compile fully on the phone
Flutter's tools are glibc/x86 binaries; Termux is bionic. Use proot Ubuntu for Flutter, Termux for the C++ lib.
1. Termux: `pkg install git clang binutils unzip proot-distro openjdk-17`
2. Native lib (Termux, bionic): `bash native/build_android.sh` after step 4 below creates the project; or run `CXX=clang++ bash native/build_android.sh`.
3. `proot-distro install ubuntu && proot-distro login ubuntu --bind $HOME:/host`
4. In Ubuntu: `apt update && apt install -y openjdk-17-jdk git curl unzip xz-utils zip python3 aapt`
   `git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter && export PATH=$HOME/flutter/bin:$PATH`
   Android cmdline-tools (Java, works on arm64): install into ~/android-sdk, then `sdkmanager "platforms;android-35" "build-tools;35.0.0"`; `flutter config --android-sdk ~/android-sdk`; `flutter doctor --android-licenses`
5. Gradle downloads an x86-64 aapt2 that cannot run on arm64. Point Gradle at an arm64 one: add to `android/gradle.properties`:
   `android.aapt2FromMavenOverride=/usr/bin/aapt2` (check `which aapt2`; if missing, find an aarch64 build).
6. `bash tools/setup_project.sh ~/app` (skips native build if already built), then `cd ~/app && flutter pub get && flutter build apk --release --target-platform android-arm64`
7. APK: `~/app/build/app/outputs/flutter-apk/app-release.apk` -> copy to /host/storage/downloads.
If any step fights you, use Path B.

## Testing order (do not skip)
1. `bash native/cpp/tests/run_tests.sh` (any machine with g++/clang++; also in Termux: `pkg install clang` then `CXX=clang++ bash ...`).
2. Install APK, paste a **Demo** PAT. App defaults to the Demo account.
3. Watch TICKS and LIVE ANALYSIS for a few minutes; open EXECUTION > PERF.
4. START with stake at the minimum on Demo. Toggle airplane mode during a run to check reconnect.
5. Only after clean Demo runs consider Real, with small stake and tight max daily loss.


## Upgrade notes (v2)
- Loss-Deviation Filter: engine-level, compares exact doubled-integer deviations (cur-prev). Strategy tab > GLOBAL FILTER.
- Clear Trade History (History tab): clears trades/win-loss/stats only. Risk accumulators (session/daily P/L, consecutive losses) are kept so limits still work.
- Currency View (Settings): USD or KES, display only, user-set rate (default 129.00, not live).
- Saved engine state from v1 is ignored once (snapshot format v2). Nothing is traded from it.

## Upgrade notes (v3 - DeltaDesk branding)
- App label/titles = "DeltaDesk". Package id (com.example.deriv_bot) is unchanged on purpose, so the APK installs OVER the old app.
- Outcome digit: last digit of the settled contract's `exit_spot` (Deriv removed `exit_tick_display_value` in the new API), computed with the market's pip size. Fallback: the tick we received at `exit_spot_time`. If Deriv gives neither, History shows a dash. A warning mark appears only if the outcome contradicts the reported WIN/LOSS.
- Icon rebuilt from assets/branding/source_reference.jpg by tools/make_icons.py (adaptive + themed/monochrome + legacy + splash).
- "@kinuu©" footer (italic) on every screen; About panel in Settings.

## Upgrade notes (v4 - recovery directions)
- Strategy tab > RECOVERY: independent OVER/UNDER for Recovery 1 and Recovery 2. The initial trade keeps its own direction.
- Each barrier is validated against its own direction (OVER 0-8, UNDER 1-9). Stake, martingale, loss handling, reset unchanged.
- Settings saved by older versions load with both recovery directions = the old initial direction, so behaviour is identical until you change them.
- Saved engine state from earlier versions is ignored once (snapshot format v3): recovery level starts at NORMAL.

## Upgrade notes (v5 - flexible trigger mode)
- Strategy tab > TRIGGER: Trigger Digit (original) or Deviation. Only one is active.
- Deviation mode: final deviation must equal the configured signed value EXACTLY (compared inside the engine as the whole-number difference current-previous, no rounding). Steps of 0.5, range +-0.5 to +-4.5. Sign must match the Positive/Negative direction.
- Saved settings from older versions load in Trigger Digit mode, unchanged.
- Engine state from earlier versions is ignored once (snapshot format v4).

## Upgrade notes (v6 - Strategy 2)
- Strategy tab: Strategy 1 (existing trigger) and Strategy 2 are collapsible cards, each with its own ON/OFF switch (applied immediately).
- Strategy 2: three exact signed deviations. Fires when the signed deviation (current digit - average of last two digits) equals the ACTIVE deviation. Transition on a CONFIRMED result only: D1 win->D2 loss->D3, D2 win->D3 loss->D1, D3 win->D2 loss->D1.
- One shared trade slot: only one contract at a time. If both strategies qualify on the same tick, Strategy 1 trades. Results of one strategy never move the other's cycle.
- Shared with Strategy 1: market, direction/barrier by recovery level, stake, martingale, recovery, risk limits, loss-deviation filter, bot START/PAUSE/STOP.
- First time S2 is switched ON it starts at Deviation 1; switching OFF/ON later RESUMES. "Start new cycle" is the only way back to D1.
- Rejected buys and unconfirmed/unreconciled trades never move the cycle. Engine state from earlier versions is ignored once (snapshot v5).

## Upgrade notes (v7 - shared barriers & cumulative loss recovery)
- Both strategies already share the global Initial / Recovery 1 / Recovery 2 barriers; recovery state is one engine-wide value, so switching strategies never resets it.
- Recovery now follows the total unrecovered loss (actual settled P/L): Initial loss -> R1; R1 loss or partial win -> R2; R2 holds until the balance is cleared; then back to Initial.
- The old "After a win RESET/STEP DOWN" setting is superseded and ignored. Snapshot format v6 (old saved state is ignored once).

## Upgrade notes (v8 - persistent martingale stake during recovery)
- With Martingale on, the stake progression is kept for the whole recovery cycle (any strategy, any recovery barrier) until the unrecovered loss is fully cleared; only then does the stake return to the configured initial stake.
- Fixed the clipped "Deviation 1" field title inside the collapsible strategy cards (extra top padding).

## Upgrade notes (v9 - Strategy 2 consecutive counts)
- Each Strategy 2 deviation has an editable count N (1-50). N-1 deviations of the trigger's own sign must immediately precede the trigger (N=1 = trigger only, the old behaviour). Longer runs also qualify; a zero deviation breaks the run. A 0.0 trigger has no sign, so its count is not applied.
- Only the currently active deviation's count is checked; transitions, barriers, recovery and martingale are unchanged. Snapshot format v7 (old saved state ignored once).
