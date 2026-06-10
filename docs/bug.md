# bug 1 saat kecilin jadi size mirp kaya andorid di trasncript ini
"

══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY
╞═════════════════════════════════════════════════════════
The following assertion was thrown during layout:
A RenderFlex overflowed by 5.7 pixels on the bottom.

The relevant error-causing widget was:
  Column
  Column:file:///D:/2.%20Organize/1.%20Projects/audio%20convert%20to%20txt/f
  lutter_app/lib/widgets/tool_card.dart:102:28

To inspect this widget in Flutter DevTools, visit:
http://127.0.0.1:64827/HxxhvrF67HE=/devtools//#/inspector?uri=http%3A%2F%2F1
27.0.0.1%3A64827%2FHxxhvrF67HE%3D%2F&inspectorRef=inspector-0

The overflowing RenderFlex has an orientation of Axis.vertical.
The edge of the RenderFlex that is overflowing has been marked in the
rendering with a yellow and
black striped pattern. This is usually caused by the contents being too big
for the RenderFlex.
Consider applying a flex factor (e.g. using an Expanded widget) to force the
children of the
RenderFlex to fit within the available space instead of being sized to their
natural size.
This is considered an error condition because it indicates that there is
content that cannot be
seen. If the content is legitimately bigger than the available space,
consider clipping it with a
ClipRect widget before putting it in the flex, or using a scrollable
container rather than a Flex,
like a ListView.
The specific RenderFlex in question is: RenderFlex#6cce0 OVERFLOWING:
  creator: Column ← LayoutBuilder ← Padding ← Padding ← DecoratedBox ←
  ConstrainedBox ← Container ←
    AnimatedContainer ← Listener ← RawGestureDetector ← GestureDetector ←
    Semantics ← ⋯
  parentData: offset=Offset(0.0, 0.0) (can use size)
  constraints: BoxConstraints(w=90.6, h=74.3)
  size: Size(90.6, 74.3)
  direction: vertical
  mainAxisAlignment: start
  mainAxisSize: max
  crossAxisAlignment: start
  textDirection: ltr
  verticalDirection: down
  spacing: 0.0
◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤
◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤
════════════════════════════════════════════════════════════════════════════
════════════════════════

Another exception was thrown: A RenderFlex overflowed by 5.7 pixels on the
bottom.
Another exception was thrown: A RenderFlex overflowed by 24 pixels on the
bottom.
Another exception was thrown: A RenderFlex overflowed by 5.7 pixels on the
bottom.
Another exception was thrown: A RenderFlex overflowed by 5.7 pixels on the
bottom.
Another exception was thrown: RenderFlex children have non-zero flex but
incoming height constraints are unbounded.
Another exception was thrown: RenderBox was not laid out:
RenderRepaintBoundary#db485 NEEDS-LAYOUT NEEDS-PAINT
"
