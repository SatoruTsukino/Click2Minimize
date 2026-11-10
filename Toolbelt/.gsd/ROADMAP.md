---
milestone: v1.0
version: 1.0.0
updated: 2026-11-09T00:00:00Z
---

# Roadmap

> **Current Phase:** 7 - Radial convert ring (done)
> **Status:** verifying (user hand test)

## Must-Haves (from SPEC)

- [ ] Dock click minimizes / hides frontmost app
- [ ] Shake-to-shelf with drag in/out and Quick Look
- [ ] Image + video/audio conversion from the shelf (optional ffmpeg/soffice)
- [ ] Per-app volume, mute, meters, persistence
- [x] Idle-cheap: no polling, taps only when needed

---

## Phases

### Phase 1: Foundation
**Status:** ✅ Complete
**Objective:** Buildable menu bar app shell: project, prefs, permissions, launch at login, popover skeleton, test target with startup guard.
**Requirements:** SHELL-01, SHELL-02, SHELL-03, SHELL-04, PACK-01

**Plans:**
- [x] Plan 1.1: Project + app shell

---

### Phase 2: Dock click
**Status:** ✅ Complete
**Objective:** Event tap + AX Dock hit-test → minimize or hide.
**Requirements:** DOCK-01..04
**Depends on:** Phase 1

**Plans:**
- [x] Plan 2.1: Dock click controller

---

### Phase 3: Shelf + convert
**Status:** ✅ Complete
**Objective:** Shake detector, shelf panel, ingest, drag out, Quick Look, conversion engine.
**Requirements:** SHLF-01..04, CONV-01..05
**Depends on:** Phase 1

**Plans:**
- [x] Plan 3.1: Shake shelf
- [x] Plan 3.2: Conversion engine + shelf actions

---

### Phase 4: Mixer
**Status:** ✅ Complete
**Objective:** Core Audio process taps with gain, mute, meters, persistence.
**Requirements:** MIX-01..06
**Depends on:** Phase 1

**Plans:**
- [x] Plan 4.1: Audio engine + mixer UI

---

### Phase 5: Package
**Status:** ✅ Complete
**Objective:** DMG + README.
**Requirements:** PACK-02
**Depends on:** Phases 2–4

**Plans:**
- [x] Plan 5.1: DMG script + README

---

### Phase 6: Hand-test gap closure
**Status:** ✅ Complete (awaiting round-2 retest)
**Objective:** Fix hand-test failures 6.4, 7.1 and notes on 4.1/4.2/4.4/6.1/6.2.
**Requirements:** SHELL-05, SHLF-05, SHLF-06, MIX-07, MIX-08

**Plans:**
- [x] Plan 6.1: Gap closure (round 1)
- [x] Plan 6.2: Gap closure (round 2)
- [x] Plan 6.3: Active-use CPU (R3.4)

---

### Phase 7: Radial convert ring
**Status:** ✅ Complete (awaiting hand test)
**Objective:** Convertino-style Shift ring during drags, results to the shelf.
**Requirements:** RING-01..04

**Plans:**
- [x] Plan 7.1: Radial convert ring

---

## Progress Summary

| Phase | Status | Plans | Complete |
|-------|--------|-------|----------|
| 1 | ✅ | 1/1 | 2026-11-09 |
| 2 | ✅ | 1/1 | 2026-11-09 |
| 3 | ✅ | 2/2 | 2026-11-09 |
| 4 | ✅ | 1/1 | 2026-11-09 |
| 5 | ✅ | 1/1 | 2026-11-09 |
| 6 | ✅ | 3/3 | 2026-11-09 |
| 7 | ✅ | 1/1 | 2026-11-09 |
