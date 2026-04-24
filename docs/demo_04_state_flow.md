# Demo State Flow

## High-Level States

1. Boot
2. Title
3. Narrative
4. Scene Interaction
5. Battle
6. Results
7. Save / Load

## Allowed Transitions

- Boot -> Title
- Title -> Narrative
- Narrative -> Scene Interaction
- Scene Interaction -> Narrative
- Narrative -> Battle
- Battle -> Results
- Results -> Narrative
- Narrative -> Title

## Persistence Scope

The first persistence pass only needs to record:

- current flow step
- unlocked scenes in the slice
- latest completed battle
- basic player state

## Engineering Constraint

All transitions should go through one flow controller so later chapter expansion does not scatter state logic across many scenes.
