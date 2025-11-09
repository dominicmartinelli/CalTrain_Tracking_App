# Caltrain Tracking App - TODO List

**Generated:** November 3, 2025
**Last Updated:** November 8, 2025
**Total Items:** 18
**Completed:** 6
**Remaining:** 12

---

## ✅ Completed (6)

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

### 3. ~~Optimize HTTPClient dictionary cleanup from O(n log n) to O(1)~~ ✅
- **Priority:** High
- **Status:** COMPLETED (November 8, 2025)
- **Location:** `CTTracker6App.swift:4077-4080` - `HTTPClient.recordRequest()`
- **Issue:** Dictionary cleanup sorted entire dictionary (O(n log n)) then took suffix. Inefficient when rate limiting many endpoints.
- **Solution:** Changed to O(1) operation that finds and removes only the oldest entry.
- **Files Changed:**
  - `CTTracker6App.swift:4077-4080` - Optimized dictionary cleanup

### 5. ~~Reduce arrival time matching tolerance from ±5 to ±2 minutes~~ ✅
- **Priority:** Medium
- **Status:** COMPLETED (November 8, 2025)
- **Location:** `CTTracker6App.swift:3812` - `GTFSService.getArrivalTime()`
- **Issue:** ±5 minute tolerance for matching departure times could match wrong trip if trains run close together
- **Solution:** Reduced tolerance to ±2 minutes for more accurate trip matching.
- **Files Changed:**
  - `CTTracker6App.swift:3812` - Changed tolerance from 5 to 2 minutes

### 13. ~~Replace all print() statements with debugLog()~~ ✅
- **Priority:** Low
- **Status:** COMPLETED (November 8, 2025)
- **Locations:** Throughout codebase (28 occurrences)
- **Issue:** Many `print()` statements execute in production builds, causing console noise
- **Solution:** Replaced all `print()` with `debugLog()` which respects DEBUG flag.
- **Files Changed:**
  - `CTTracker6App.swift` - 28 print() statements replaced with debugLog()

### 18. ~~Fix nil userInfo in notification posting~~ ✅
- **Priority:** Low
- **Status:** COMPLETED (November 8, 2025)
- **Investigation Result:** No NotificationCenter.default.post() calls found in codebase. All NSError objects properly include userInfo dictionaries. Warning is from iOS internals (UIKit/SwiftUI), not app code.
- **Conclusion:** No code changes needed - warning is system-level, not under app control.

---

## 🔴 High Priority - Performance (1)

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

## 🟡 Medium Priority - Bugs (5)

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

## 🟢 Code Quality (3)

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
- **Recommended Fix:** Extract to named constants at top of file or in configuration struct
  ```swift
  private enum GTFSConfig {
      static let maxDecompressionSize = 50_000_000 // 50MB
      static let maxCompressionRatio = 100.0
  }
  ```
- **Impact:** Hard to maintain, unclear intent

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

## 🔵 Low Priority - Warnings (1)

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

---

## 📊 Summary

| Priority | Count | Items |
|----------|-------|-------|
| ✅ Completed | 6 | Data race, GTFS decompression, HTTPClient optimization, Arrival tolerance, Print statements, Notification investigation |
| 🔴 High | 1 | Delay prediction optimization |
| 🟡 Medium | 5 | Direction matching, iMessage validation, History limit, Test data, Date math |
| 🟢 Code Quality | 3 | Duplicate code, Magic numbers, Nil checks |
| 🏗️ Architecture | 2 | File splitting, Error handling standardization |
| 🔵 Low Priority | 1 | UIReparentingView warning |

---

## 🎯 Recommended Order of Implementation

### Phase 1: Quick Wins ✅ COMPLETED (November 8, 2025)
1. ✅ HTTPClient dictionary cleanup (Item #3)
2. ✅ Reduce arrival time tolerance (Item #5)
3. ✅ Replace print() statements (Item #13)
4. ✅ Fix notification userInfo (Item #18)

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
- **Phase 1 Quick Wins completed** (Nov 8, 2025) - Performance optimizations and code quality improvements
- **Simulator warnings** - Most error messages are simulator-only and safe to ignore
- **Test on physical device** - Verify fixes work correctly on actual hardware
- **Incremental improvements** - Tackle these items over time, prioritize based on user feedback

**Last Updated:** November 8, 2025
