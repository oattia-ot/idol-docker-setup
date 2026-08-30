# Eduction Processor Configuration

**Processor:** Eduction 26.1.0-nifi2 | **Document Type:** Configuration Change Record

---

## Overview

This document records the configuration changes applied to the Eduction 26.1.0-nifi2 NiFi processor. Two properties were modified from their defaults as part of this configuration update:

| Property | Tab / Section | Previous Value | New Value |
|---|---|---|---|
| Allow Multiple Results | Properties | *(default)* | **OnePerEntity** |
| Enable Components | Properties | `false` | **`true`** |

---

## Change 1 — Allow Multiple Results

| Field | Value |
|---|---|
| Property Name | Allow Multiple Results |
| Location | Properties Tab |
| Set Value | **OnePerEntity** |

### Description

The `Allow Multiple Results` property controls how the Eduction engine handles multiple candidate matches within a single entity. Setting this to `OnePerEntity` instructs the processor to return only a single result per identified entity, selecting the highest-confidence or first match rather than emitting all candidates.

This is particularly useful in scenarios where downstream processing expects exactly one result per entity and duplicate or redundant matches would cause issues in the data pipeline.

---

## Change 2 — Enable Components

| Field | Value |
|---|---|
| Property Name | Enable Components |
| Location | Properties Tab |
| Set Value | **`true`** |

### Description

The `Enable Components` property controls whether the Eduction processor outputs component-level information alongside entity matches. When set to `true`, the processor will include sub-entity component data in its output, providing richer structured results that break down each matched entity into its constituent parts.

Enabling this setting is important when the downstream system requires granular field-level extraction from entities (for example, separating first name, last name, and title from a person entity match).

---

## Full Properties Snapshot

| Property | Value | Changed |
|---|---|---|
| Table Header Entity | *(No value set)* | |
| Table Max Search Header Row | `1` | |
| Allow Multiple Results | **`OnePerEntity`** | ✅ Yes |
| Case Normalization Behavior | `Default` | |
| Count Output | `false` | |
| Enable Components | **`true`** | ✅ Yes |
| Enable Unique Matches | `false` | |
| Inline Results | `false` | |
| Match Case | `true` | |

---

*Processor: Eduction 26.1.0-nifi2 | Verification status: Pending (click Verify in UI to confirm)*