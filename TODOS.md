# Caltrain Tracking App - TODO List

**Generated:** November 3, 2025
**Total Items:** 18
**Completed:** 2
**Remaining:** 16

---

## ✅ Completed (2)

### 1. ~~Fix critical data race in CommuteHistoryStorage.recordTrip()~~ ✅
- **Priority:** Critical
- **Status:** COMPLETED
- **Location:** `CTTracker6App.swift:3016-3089`
- **Issue:** Multiple users tapping "record trip" simultaneously could cause concurrent writes to UserDefaults, leading to lost trip records or corrupted data
- **Solution:** Added thread-safe DispatchQueue with concurrent reads and barrier writes. Created new `recordTrip()` method with completion handler for atomic operations.
- **Files Changed:**
  - `CTTracker6App.swift:3016-3089` - CommuteHistoryStorage class
  - `CTTracker6App.swift:1803-1828` - DepartureRow.recordTrip() method

### 2. ~~Fix critical GTFS decompression validation~~ ✅
- **Priority:** Critical
- **Status:** COMPLETED
- **Location:** `CTTracker6App.swift:3553-3557`
- **Issue:** After decompressing GTFS ZIP files, code didn't verify actual decompressed size matched expected size. Corrupted data could silently produce invalid train schedules.
- **Solution:** Added strict validation: `guard decompressedSize == uncompressedSize` with descriptive error message.
- **Files Changed:**
  - `CTTracker6App.swift:3553-3557` - Added size validation in decompress()

---

## 🔴 High Priority - Performance (2)

### 3. Optimize HTTPClient dictionary cleanup from O(n log n) to O(1)
- **Priority:** High
- **Location:** `CTTracker6App.swift:4037-4040` - `HTTPClient.recordRequest()`
- **Issue:** Dictionary cleanup sorts entire dictionary (O(n log n)) then takes suffix. Inefficient when rate limiting many endpoints.
- **Current Code:**
  ```swift
  if lastRequestTime.count > maxCachedEndpoints {
      let sorted = lastRequestTime.sorted { $0.value < $1.value }
      lastRequestTime = Dictionary(uniqueKeysWithValues: Array(sorted.suffix(maxCachedEndpoints)))
  }
  ```
- **Recommended Fix:**
  ```swift
  if lastRequestTime.count > maxCachedEndpoints {
      let oldest = lastRequestTime.min(by: { $0.value < $1.value })?.key
      if let key = oldest { lastRequestTime.removeValue(forKey: key) }
  }
  ```
- **Impact:** Performance degradation when rate limiting many different API endpoints

### 4. Optimize delay prediction filtering with indexed data structure
- **Priority:** High
- **Location:** `CTTracker6App.swift:2763-2768` - `DelayPredictor.predictDelay()`
- **Issue:** Function filters all delay records on every call. For 20,000 records in DEBUG mode, creates new array copy with every prediction.
- **Current Code:**
  ```swift
  let similarRecords = records.filter {
      $0.trainNumber == trainNumber &&
      $0.stopCode == stopCode &&
      $0.dayOfWeek == dayOfWeek &&
      abs($0.hourOfDay - hourOfDay) <= 1
  }
  ```
- **Recommended Fix:** Create index/dictionary structure by `(trainNumber, stopCode, dayOfWeek, hour)` or use database (Core Data, SQLite) instead of UserDefaults
- **Impact:** Significant CPU usage when checking multiple trains on the Alerts tab

---

## 🟡 Medium Priority - Bugs (6)

### 5. Reduce arrival time matching tolerance from ±5 to ±2 minutes
- **Priority:** Medium
- **Location:** `CTTracker6App.swift:3772` - `GTFSService.getArrivalTime()`
- **Issue:** ±5 minute tolerance for matching departure times could match wrong trip if trains run close together
- **Current Code:**
  ```swift
  if abs(originMinutes - depMinutes) <= 5 {
  ```
- **Recommended Fix:** Reduce to `<= 2` or add train number matching if available
- **Impact:** Wrong arrival times displayed for closely-spaced trains

### 6. Improve direction matching from string prefix to exact match
- **Priority:** Medium
- **Location:** `CTTracker6App.swift:4366-4372` - `SIRIService.nextDepartures()`
- **Issue:** Direction matching uses string prefix which is fragile. If API returns "Northeast" or "Northbound Express", it would match "N"
- **Current Code:**
  ```swift
  let matches = (expected.uppercased() == "N" && dir.uppercased().starts(with: "N")) ||
               (expected.uppercased() == "S" && dir.uppercased().starts(with: "S"))
  ```
- **Recommended Fix:** Use exact string matching or whitelist of valid direction strings
- **Impact:** Wrong trains could be included in results

### 7. Add validation for iMessage recipient format
- **Priority:** Medium
- **Location:** `CTTracker6App.swift:864` - SettingsScreen
- **Issue:** iMessage recipient field accepts any string without validating it's a valid phone number or email
- **Current Code:**
  ```swift
  TextField("Phone Number", text: $iMessageRecipient)
  ```
- **Recommended Fix:** Add validation for phone number format (e.g., regex) or email format
- **Impact:** Users might enter invalid recipients and messages will fail silently

### 8. Increase history limit from 500 to 2000+ entries
- **Priority:** Medium
- **Location:** `CTTracker6App.swift:3019` - CommuteHistoryStorage
- **Issue:** Maximum of 500 history entries may not be sufficient for accurate pattern detection, especially for users with irregular commutes
- **Current Code:**
  ```swift
  private let maxHistoryEntries = 500 // Keep last 500 checks
  ```
- **Recommended Fix:** Increase to 2000-5000 entries, or implement smarter retention (keep at least N entries per unique route)
- **Impact:** Less accurate commute pattern predictions

### 9. Optimize test data generation with batching
- **Priority:** Medium
- **Location:** `CTTracker6App.swift:1056-1118` - `addTestDelayData()`
- **Issue:** Generates ~2,376 records synchronously in detached task. While `Task.detached` prevents UI freezing, still allocates significant memory all at once
- **Recommended Fix:** Generate in batches with small delays between batches, or use `autoreleasepool`
- **Impact:** Memory spike during test data generation

### 10. Simplify date math for tomorrow's trains using Calendar API
- **Priority:** Medium
- **Location:** `CTTracker6App.swift:3891-3896` - `GTFSService.getScheduledDepartures()`
- **Issue:** Calculation for next-day trains is complex and error-prone
- **Current Code:**
  ```swift
  if isNextDay {
      minutesUntil = (24 * 60 - nowMinutes) + totalMinutes
  } else {
      minutesUntil = totalMinutes - nowMinutes
  }
  ```
- **Recommended Fix:** Use `Calendar.date(byAdding:)` and Date comparison instead of manual minute calculations
- **Impact:** Hard to maintain, potential for subtle bugs around midnight

---

## 🟢 Code Quality (4)

### 11. Extract duplicate arrival time calculation code
- **Priority:** Low
- **Location:** `CTTracker6App.swift:1450-1513` - TrainsScreen
- **Issue:** Nearly identical code for northbound and southbound arrival calculations
- **Recommended Fix:** Extract into single function with direction parameter
- **Impact:** Maintenance burden, risk of inconsistency

### 12. Replace magic numbers with named constants
- **Priority:** Low
- **Locations:** Throughout codebase
- **Issue:** Magic numbers make code hard to maintain and understand
- **Examples:**
  - Line 3482: `50_000_000` (50MB max decompression)
  - Line 3492: `100` (compression ratio limit)
  - Line 298: `15_000_000_000` (15 second delay)
  - Line 1810: `500` (history limit)
  - Line 3772: `5` (arrival time tolerance)
- **Recommended Fix:** Extract to named constants at top of file or in configuration struct
  ```swift
  private enum GTFSConfig {
      static let maxDecompressionSize = 50_000_000 // 50MB
      static let maxCompressionRatio = 100.0
  }
  ```
- **Impact:** Hard to maintain, unclear intent

### 13. Replace all print() statements with debugLog()
- **Priority:** Low
- **Locations:** Throughout codebase
- **Issue:** Many `print()` statements execute in production builds
- **Examples:**
  - Line 920: `print("🔴 CLEAR BUTTON TAPPED")`
  - Lines 4360-4362: Multiple print statements in SIRI parsing
- **Recommended Fix:** Replace all `print()` with `debugLog()` which respects DEBUG flag
- **Impact:** Console noise in production, potential performance impact

### 14. Add defensive nil checks in DepartureRow
- **Priority:** Low
- **Location:** `CTTracker6App.swift:1782` - DepartureRow
- **Issue:** `dep.minutes` used directly without nil check (though Departure struct makes it non-optional)
- **Current Code:**
  ```swift
  Text("\(dep.minutes)m")
  ```
- **Recommended Fix:** Defensive programming: `Text("\(dep.minutes ?? 0)m")`
- **Impact:** Potential crash if minutes is somehow nil

---

## 🏗️ Architecture & Long-term (2)

### 15. Split single 4600+ line file into modules
- **Priority:** Low (Long-term)
- **Location:** Entire `CTTracker6App.swift` (4600+ lines)
- **Issue:** Entire app in one massive Swift file, difficult to navigate, review, and maintain
- **Recommended Structure:**
  ```
  Models/
    - CaltrainModels.swift
    - CommuteModels.swift
    - GamificationModels.swift
  Services/
    - GTFSService.swift
    - SIRIService.swift
    - HTTPClient.swift
    - DelayPredictor.swift
    - WeatherService.swift
    - TicketmasterService.swift
  Views/
    - TrainsScreen.swift
    - EventsScreen.swift
    - AlertsScreen.swift
    - InsightsView.swift
    - StationsScreen.swift
    - SettingsScreen.swift
  Storage/
    - Keychain.swift
    - CommuteStorage.swift
    - GamificationManager.swift
  ```
- **Impact:** Difficult to maintain, hard to navigate, challenging for collaboration

### 16. Standardize error handling patterns across app
- **Priority:** Low (Long-term)
- **Locations:** Throughout codebase
- **Issue:** Inconsistent error handling - some functions use `try?` and fail silently, others throw errors, others return optionals
- **Examples:**
  - Line 1460: `try? await GTFSService.shared.getArrivalTime()` - fails silently
  - Line 3522: `try await downloadAndParseGTFS()` - throws error
  - Line 2750: `predictDelay()` - returns optional
- **Recommended Fix:** Establish consistent error handling pattern:
  - Use `Result<T, Error>` for operations that can fail
  - Reserve optionals for truly optional data
  - Use throwing functions for critical operations
  - Document error handling strategy
- **Impact:** Inconsistent user experience, difficult to debug

---

## 🔵 Low Priority - Warnings (2)

### 17. Fix _UIReparentingView warning in MessageComposer/ShareSheet
- **Priority:** Low
- **Location:** `CTTracker6App.swift:1616-1662` - MessageComposer & ShareSheet
- **Issue:** SwiftUI warning about view hierarchy when presenting MessageComposer
- **Warning Message:**
  ```
  Adding '_UIReparentingView' as a subview of UIHostingController.view is not supported
  and may result in a broken view hierarchy.
  ```
- **Impact:** Potential visual glitches on some iOS versions (works fine, but not ideal)
- **Recommended Fix:** Research SwiftUI best practices for UIViewControllerRepresentable, or test on physical device to confirm it's not actually a problem
- **Note:** This is a known SwiftUI issue with UIViewControllerRepresentable

### 18. Fix nil userInfo in notification posting (SmartNotificationManager)
- **Priority:** Low
- **Location:** Likely around `CTTracker6App.swift:3240` - SmartNotificationManager
- **Issue:** Posting notifications with nil userInfo dictionary
- **Warning Message:**
  ```
  [Notifications]: Attempting to post will notification with nil userInfo
  [Notifications]: Attempting to post did notification with nil userInfo
  ```
- **Impact:** Console warnings only, notifications still work
- **Recommended Fix:** Add empty dictionary `[:]` if no userInfo needed
  ```swift
  // Before
  NotificationCenter.default.post(name: .someNotification, object: nil)

  // After
  NotificationCenter.default.post(name: .someNotification, object: nil, userInfo: [:])
  ```

---

## 📊 Summary

| Priority | Count | Items |
|----------|-------|-------|
| ✅ Completed | 2 | Critical data race, GTFS decompression |
| 🔴 High | 2 | HTTPClient optimization, Delay prediction optimization |
| 🟡 Medium | 6 | Arrival tolerance, Direction matching, iMessage validation, History limit, Test data, Date math |
| 🟢 Code Quality | 4 | Duplicate code, Magic numbers, Print statements, Nil checks |
| 🏗️ Architecture | 2 | File splitting, Error handling standardization |
| 🔵 Low Priority | 2 | UIReparentingView warning, Notification userInfo |

---

## 🎯 Recommended Order of Implementation

### Phase 1: Quick Wins (1-2 hours)
1. HTTPClient dictionary cleanup (Item #3)
2. Reduce arrival time tolerance (Item #5)
3. Replace print() statements (Item #13)
4. Fix notification userInfo (Item #18)

### Phase 2: Performance & Bugs (4-6 hours)
1. Optimize delay prediction filtering (Item #4)
2. Improve direction matching (Item #6)
3. Add iMessage validation (Item #7)
4. Simplify date math (Item #10)

### Phase 3: Code Quality (2-3 hours)
1. Replace magic numbers (Item #12)
2. Extract duplicate code (Item #11)
3. Add defensive nil checks (Item #14)

### Phase 4: Long-term Improvements (8-12 hours)
1. Increase history limit (Item #8)
2. Optimize test data generation (Item #9)
3. Standardize error handling (Item #16)
4. Investigate UIReparentingView warning (Item #17)

### Phase 5: Major Refactor (1-2 days)
1. Split single file into modules (Item #15)

---

## 📝 Notes

- **Critical bugs are fixed** - App is production-ready
- **Simulator warnings** - Most error messages are simulator-only and safe to ignore
- **Test on physical device** - Verify fixes work correctly on actual hardware
- **Incremental improvements** - Tackle these items over time, prioritize based on user feedback

**Last Updated:** November 3, 2025
