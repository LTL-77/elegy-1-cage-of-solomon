# Demo Battle Spec

## Battle Pillars

- readable turn-based combat
- one visible resource tension: `Spirit`
- one long-tail narrative mechanic reserved for later: `Sin`
- small combat roster

## Slice 1 Roster

- player side: `Indels` only
- enemy side: `2` basic enemy templates and `1` boss

## Visible Stats

- HP
- ATK
- DEF
- SPD
- Spirit

## First Slice Rules

### Turn Order

- all combatants are sorted by `SPD` descending
- ties resolve by side priority, then stable order

### Basic Attack

- cost: `0 Spirit`
- cooldown: `0`
- damage: `ATK - target DEF`, minimum `1`

### Spirit Skill

- consumes Spirit
- power scales from a fixed coefficient and current Spirit band
- may not reduce Spirit below the exhaustion threshold

### Spirit Recovery

- recover a small fixed amount at the start of the unit's turn
- recovery cannot exceed max Spirit

### Exhaustion

- if Spirit would fall below the lower threshold, the unit dies immediately

### Overload

- if Spirit exceeds max Spirit, mark the unit as overloaded
- overloaded units survive for a fixed countdown
- when the countdown ends, the unit dies

## Deferred Systems

The following stay out of implementation until the vertical slice is stable:

- full Sin accumulation
- full inversion stages
- support pair mechanics
- equipment interactions
- multi-target skill language
- chapter-specific modifiers
