# Study Tool

## Purpose

Study is a focused, full-screen way to explore one Insight without losing the user’s place in the Insight Tree. It is designed to make abstract relationships tangible: the selected Insight becomes the stable center of the experience, while the surrounding dot matrix communicates the active exploration tool and its state.

The view is intentionally reusable. Today it is presented from a hovered Insight in the conversation tree; the same view can later be used by the standalone Insights page.

## Entry and exit

1. The user hovers an Insight in the tree and selects **Study** (`graph.3d`).
2. The selected Insight chip contracts to its bubble icon as the Study overlay fades in above the canvas. This preserves the sense that Study is a focused state of the same object, rather than a replacement navigation hierarchy.
3. The title fades and deblurs above a matrix whose center remains at the canvas focal point. The dot matrix resolves over its randomized entrance sequence; the center symbol is already present when Study is entered from the tree, while standalone callers may opt into its distinct entrance.
4. The existing **Back** control exits Study and returns to the hovered Insight in the tree. Pressing Back again follows the existing conversation navigation behavior.

No duplicate Return or Exit control is introduced for Study. This keeps the navigation model consistent across the app.

## Layout

`StudyModeView` owns the focused screen. Its vertical arrangement is:

1. Insight title
2. 300 × 300 point circular dot matrix
3. Tool switcher and short explanation

The title and matrix use a 20-point gap and are positioned as one cluster around the fixed matrix center. The carousel remains below the matrix. The matrix has a fixed frame so switching tools does not cause the rest of the screen to move or resize.

## Tool switcher

The switcher currently contains three tools:

| Tool | Intent | Current matrix behavior |
| --- | --- | --- |
| Branch | Generate nearby related Insights | Shows selectable outer-ring destinations for 2–6 new Insights. |
| Deconstruct | Break an Insight into semantic parts | Forms a fourth-ring decomposition band, then transfers its 2 o’clock marker outward. |
| Traverse | Move through a semantic direction | Copy and interaction shell only; visual behavior is reserved for vector-space traversal. |

Users can use the arrow controls or swipe horizontally in the switcher below the dot matrix to change the active tool. The last selected tool is retained for the next Study session. Matrix gestures are reserved for the active tool, preventing a Branch count rotation from accidentally changing tools. Copy slides in from the direction of travel while the outgoing copy leaves in the opposite direction. Tool changes do not currently emit a generic haptic; tool-specific haptics are reserved for meaningful interactions.

## Dot matrix

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

`StudyBranchDockControls` presents the count selector and the future **Place** action as independent pills. Both are 68 points high. The count pill begins expanded; it contracts smoothly as the Place pill opens into the freed space. Place uses an 8-point blur-to-clear transition, fades in, and settles from 1.05× to its final scale.

The Place action currently provides tactile confirmation only. Its eventual responsibility is to commit the generated related Insights into the tree.

## Deconstruct

Deconstruct begins by highlighting every dot in the fourth ring from the center. Those dots reveal in a shuffled order, using the same individual haptic-arrival treatment as Branch markers. After the ring has had time to complete, its 2 o’clock dot returns to the normal base-dot treatment while the matching 2 o’clock dot on the sixth (outer) ring grows into a persistent highlighted marker and registers a haptic.

This outward transfer is the first visual metaphor for decomposition: a selected semantic component separates from the Insight’s local structure and becomes available for further inspection.

## State and integration

`CanvasModeModel` holds the cross-view state needed by Study:

- Whether Study is active or exiting
- The request tokens used to enter and exit it from the tree
- The Branch count (2–6)

`InsightTreeView` coordinates the overlay with the existing Insight Tree selection and back-navigation behavior. `StudyModeView` receives only the focused Insight, the current Branch count, the exit state, and a narrow count-change callback. This keeps the focused view independent of the larger canvas implementation and ready for reuse on the standalone Insights page.

## Relevant implementation files

| File | Responsibility |
| --- | --- |
| `Aquinas-iOS/Features/InsightTree/StudyModeView.swift` | Study layout, matrix, tool switcher, Branch patterns, entrance motion, and radial count gesture. |
| `Aquinas-iOS/Features/InsightTree/InsightTreeView.swift` | Presents and dismisses Study above the Insight Tree. |
| `Aquinas-iOS/Features/Conversation/StudyBranchDockControls.swift` | Branch count and Place controls in the persistent dock. |
| `Aquinas-iOS/Features/Canvas/CanvasModeModel.swift` | Shared Study mode and Branch-count state. |

## Planned extensions

- Extend Deconstruct from this visual structure into a token-level semantic decomposition of the selected Insight.
- Implement Traverse as a directional vector-space exploration tool.
- Make Place create and position the requested related Insights.
- Reuse `StudyModeView` unchanged from the standalone Insights page.
- Add focused tests for Branch count bounds, radial gesture direction, and exact clock-position selection.
