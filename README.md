# Insight

A calm, minimal Flutter app (Android) that tracks **gold, silver and platinum** and tells you when something matters.

## Features
- **Today** — swipe between Gold / Silver / Platinum. Price per gram (USD or INR), streak bars, touch-to-scrub chart (1D–1Y), Buy / Hold / Sell signal with confidence, and *Why it moved* (ranked likely reasons from dollar index, bond yields and live news headlines).
- **Ask Google** — the globe button opens Google AI Mode with a "why did the price move" question for that metal and day.
- **Alerts** — rising/falling streaks, trend flips, sudden moves (%/hour), price targets, quiet hours. All alerts are sent as *Important*.
- **Daily briefs** at 9 AM and 9 PM.
- Background checks every 15 minutes (WorkManager).

## Pricing
- Live spot prices: gold-api.com; history/indicators: Yahoo Finance.
- INR shows the Indian market rate: gold follows Paytm's published 24K rate, silver follows Groww, platinum follows the Indian market rate (StockeZee). These pages are read at most 3×/day and scaled with the live spot price in between. Tap the source chip to switch to international spot.
- Rate-limited/free sources (exchange rates, news, rate pages) are cached for 8 hours.

## Build & install
```sh
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```
Requires Flutter 3.50+ and Android SDK platform 37.

Signals are rule-based indicators, not financial advice.
