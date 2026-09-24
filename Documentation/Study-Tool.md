# Study Tool

## Purpose

Study is a focused way to explore a Node Concept and its Insights in full 3D without losing
the user's place in the Insight Tree. It is not a separate screen with a copy of the node: the
tree canvas moves its own camera into a 3D view of the node the user was looking at, fades the
rest of the tree, and moves back on exit.

## Entry and exit

1. The user hovers a Node Concept or an Insight in the tree and selects **Study**
   (`graph.3d`). Hovering an Insight and choosing Study opens its parent Node Concept with that
   Insight hovered.
2. The docked card scales away (the same transition as switching Insights), then the Study
   tool card pops up in its place (the same transition as hovering an Insight).
3. The tree's camera swings from overhead to eye level over 0.8 s and flies the node into the
   300 × 300 Study slot. Everything else in the tree moves with the same camera while it
   fades; the flat dot grid fades into a receding dot floor. The node's Insights leave the
   tree's ±45° band and spread over a sphere around it.
4. The side-menu button grows an **× Exit** capsule. Exit hands the dock and card back
   immediately, then moves the camera back into the tree (any whole turns are dropped first,
   so it unwinds at most half a turn). Whatever was hovered in Study stays hovered.

## The 3D view

| Element | Behavior |
| --- | --- |
| Camera | Level with the node, looking down at a floor ring. Opens at 2× zoom. |
| Insights | Tree-sized chips spread over a sphere (Thomson repulsion from their tree directions, deterministic). Chips behind the node dim smoothly and draw behind it. |
| Ring | A dashed 300 × 42 ellipse 24 pt above the tool card; gradient 5% (far) to 40% (near). Stays fixed while the user pans or zooms. Its dashes turn with the node. |
| Floor | The tree's dot grid laid on the ring's plane at 50% opacity, receding toward the horizon. It moves 1:1 with the node camera. |

Gestures (Study only; the tree's own gestures are off):

- **Drag the ring** to spin the node like a turntable (detent haptic every 15°). Releasing
  mid-swipe keeps it turning and easing to a stop. The ring brightens and grows 5% while held.
- **Drag elsewhere** to pan. **Pinch** to zoom (0.5×–5×).
- **Tap an Insight** to hover it, exactly like hovering in the tree (haptic, card state, and
  connector pulse). The camera centers it 70 pt below the node's spot with the tree's hover
  spring, zooms in by the tree's hover amount measured from Study's opening zoom, and makes it
  the axis of rotation. A hovered Insight never dims.
- **Tap the node** to hover it; the camera glides back to center it.
- **Pan off a hovered Insight** to unhover it; the hover returns to the node and the axis of
  rotation returns to the node's center without moving the view.

## Tool card

The Branch / Deconstruct / Traverse switcher lives in `StudyToolCard`, a docked card with the
Insight card's exact chrome (`dockedCardChrome`). Users can tap the arrows or swipe to change
tools, and the last tool is retained. The tools are not yet wired to the 3D view.

## Dot matrix (retained, currently unused for most Insights)

> **Before launch:** the dot matrix is kept in case it becomes useful again. It is only
> reached from Insights without an ordinary parent Node Concept (placed midpoints). If it is
> still unused when the app goes live, remove `StudyDotMatrix`, its Branch and Deconstruct
> visuals, and the `.insight` Study subject.

`StudyDotMatrix` draws seven concentric rings around the central Insight symbol. The innermost ring is intentionally omitted, leaving visual space for the focal Insight.

### Base-dot entrance

Each base dot has a deterministic, per-Insight random delay between **0.2 and 1.0 seconds**. Dots enter concurrently rather than as a serial sweep:

- They appear at 4 points.
- They remain at their initial size for 0.2 seconds.
- They settle to 2 points over 0.16 seconds.

Each arrival registers a haptic event. Events that land within a tiny perceptual window are combined into a stronger impact, which preserves the sensation of simultaneous dots instead of letting device haptics discard overlapping requests.

## Branch

Branch turns the outer ring into a direct count selector for nearby Insights. The selected dots use true clock positions, making the formations recognizable rather than merely evenly distributed.

| New Insights | Outer-ring formation |
| ---: | --- |
| 2 | 12 and 6 |
| 3 | 2, 6, and 10 (Y shape) |
| 4 | 12, 3, 6, and 9 (diamond) |
| 5 | 12, 2, 5, 7, and 10 (pentagon) |
| 6 | 12, 2, 4, 6, 8, and 10 (hexagon) |

### Count selection

The count is constrained to 2–6 Insights and is shared with the persistent Branch controls at the bottom of the canvas.

- **Plus/minus controls** adjust the count by one.
- **Clockwise rotation** around the dot matrix increases the count.
- **Counterclockwise rotation** decreases it.
- Each approximately 36 degrees of circular drag advances one count, with a light haptic confirmation.

When the count changes, the selected Branch dots reveal in a randomized 80–320ms order. Each reveal registers its own haptic tap; near-simultaneous arrivals are strengthened by the same batching system used for base-dot entrances. Unlike the base grid, selected Branch dots remain at 8 points after arriving and use 0.86 opacity (10% brighter than the previous 0.78 treatment).

### Branch dock controls

`StudyBranchDockControls` presents the count selector and the future **Place** action as independent pills. Both are 64 points high, matching the normal dock. The count pill begins expanded; it contracts smoothly as the Place pill opens into the freed space. Place uses an 8-point blur-to-clear transition, fades in, and settles from 1.05× to its final scale.

The Place action currently provides tactile confirmation only. Its eventual responsibility is to commit the generated related Insights into the tree.

## Deconstruct

Deconstruct begins by highlighting every dot in the fourth ring from the center. Those dots reveal in a shuffled order, using the same individual haptic-arrival treatment as Branch markers. After the ring has had time to complete, its 2 o’clock dot returns to the normal base-dot treatment while the matching 2 o’clock dot on the sixth (outer) ring grows into a persistent highlighted marker and registers a haptic.

This outward transfer is the first visual metaphor for decomposition: a selected semantic component separates from the Insight’s local structure and becomes available for further inspection.

## State and integration

`CanvasModeModel` holds the cross-view state needed by Study:

- Whether Study is active or exiting
- The request tokens used to enter and exit it from the tree
- The Branch count (2–6)

`InsightTreeView` coordinates Study with the Insight Tree's selection, docked cards, and back
navigation. For a Node Concept it passes `studyNodeID`, the optional initially hovered Insight,
and the slot frame reported by `StudyModeView` to `InsightTreeCanvasView`, which owns the 3D
camera, gestures, and hover. `StudyModeView` itself only reserves the slot (or shows the dot
matrix for an Insight subject).

## Relevant implementation files

| File | Responsibility |
| --- | --- |
| `Aquinas-iOS/Features/InsightTree/StudyModeView.swift` | Study slot, tool card, and the retained dot matrix. |
| `Aquinas-iOS/Features/InsightTree/InsightTreeView.swift` | Enters and exits Study, the tool card, and hover hand-off. |
| `Aquinas-iOS/Features/InsightTree/InsightTreeCanvasView.swift` | The Study camera move, 3D positions, fades, gestures, hover, and momentum. |
| `Aquinas-iOS/Features/InsightTree/StudyNodeScene.swift` | `StudyFraming` (camera framing, ring, floor), the ring, and the dot floor. |
| `Aquinas-iOS/Features/InsightTree/StudyNodeLayout.swift` | The sphere spread and spherical interpolation. |
| `Aquinas-iOS/Features/InsightTree/InsightClusterSpatialLayout.swift` | The tree's ±45° Insight elevations. |
| `Aquinas-iOS/DesignSystem/OrbitCamera.swift`, `PerspectivePlaneProjection.swift` | The 3D camera and the tree's overhead projection. |
| `Aquinas-iOS/Navigation/SideMenu.swift` | `StudyExitButton`. |
| `Aquinas-iOS/Features/Conversation/StudyBranchDockControls.swift` | Branch count and Place controls in the persistent dock. |
| `Aquinas-iOS/Features/Canvas/CanvasModeModel.swift` | Shared Study mode and Branch-count state. |

## Planned extensions

- Extend Deconstruct from this visual structure into a token-level semantic decomposition of the selected Insight.
- Implement Traverse as a directional vector-space exploration tool.
- Make Place create and position the requested related Insights.
- Wire the tools to the 3D view.
- Remove the dot matrix before launch if it is still unused (see above).
