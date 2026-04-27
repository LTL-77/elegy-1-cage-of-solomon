# Beiyao Demo Chapter Flow

## Goal

Align the playable demo with the rewritten `北遥之乱` mainline by rebuilding the current prototype into a three-space infiltration chapter.

## Source Alignment

- Chapter 1 `废矿没有旗`
  Used for the opening atmosphere, the mine briefing, and the contract between 兵略年 and 因第尔斯.
- Chapter 2 `城会记错人`
  Used for the cargo gate arrival, the first patrol conflict, the chained laborers, and the裂隙石 logistics.
- Chapter 3 `裂隙不属于死人`
  Used for the outer-court pressure, the继名室 approach, and the thematic framing before the Boss fight.
- Chapter 4 `通报比血干净`
  Used only as a closing hook in the current demo, not as a full playable aftermath chapter.

## Playable Structure

1. `opening`
   Type: `narrative`
   Function: establish废矿、反叛组织状态、因第尔斯与兵略年的交易前提.

2. `mine_staging`
   Type: `map`
   Space: 废矿据点
   Objective: inspect the broken支道, the刻字的 working on门锚, and兵略年的安排.
   Payoff: understand that this infiltration is paid for with expendable lives.
   Understanding: first increase for accepting the operation and its cost.

3. `crossing_brief`
   Type: `narrative`
   Function: transition from废矿 to the first门锚 jump and frame the expected偏移.

4. `cargo_gate`
   Type: `map`
   Space: 货运闸门 / 旧排水槽
   Objective: inspect patrol traces,裂隙石 logistics, and chained laborers before triggering conflict.
   Payoff: make北遥的秩序 concrete.
   Understanding: second increase for seeing how the city actually runs.

5. `tutorial_battle_intro`
   Type: `narrative`
   Function: frame the first fight as a practical clash with监闸巡逻, not a generic tutorial arena.

6. `tutorial_battle`
   Type: `battle`
   Encounter: cargo gate patrol
   Function: teach the current single-character combat loop.

7. `outer_court_transition`
   Type: `narrative`
   Function: compress the consequences of the diversion and describe the cost being paid elsewhere.

8. `outer_court`
   Type: `map`
   Space: 北遥府邸外苑
   Objective: inspect the second门锚, the patrol redistribution, and the silent geometry around继名室.
   Payoff: make the player feel they are crossing into thicker layers of rule.
   Understanding: third increase for directly confronting北遥's ordered violence.

9. `antechamber`
   Type: `narrative`
   Function: set up继名室, portrait pressure, naming ritual residue, and北遥's inhuman calm.

10. `boss_approach`
    Type: `map`
    Space: 继名室前
    Objective: enter the forced trigger radius of the Boss approach.
    Payoff: remove the feeling of "clicking a dialogue option to start the Boss."

11. `boss_battle`
    Type: `battle`
    Encounter: 所罗门北遥
    Function: deliver the chapter climax.
    Understanding: fourth increase for surviving the direct confrontation and killing the host.

12. `closing`
    Type: `narrative`
    Function: reveal that the裂隙 returned upward, the city is sealing, and the incident was only the first tear.

## Implementation Notes

- Keep only three lightweight maps in this demo.
- Do not add platforming or freeform maze exploration.
- Every map should have a distinct visual theme, even if it reuses the same scene shell.
- Understanding rewards should come from chapter beats, not generic "completion bonus" feeling.
- The character archive should now read like a consequence of lived events in this chapter.
