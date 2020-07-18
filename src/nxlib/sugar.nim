import node, util
import strutils

type
  VectorParameter = tuple
    x: int
    y: int
  BinaryParameter = tuple
    kind: NxType
    data: string
  NilNode* = ref object of NxNode
    point: NxNode
    expect: string

proc name*(node: NxNode): string =
  result = node.getName

proc `name=`*(node: NxNode, name: string) =
  node.setName(name)

proc `+=`*(parent: NxNode, name: string) =
  discard parent.addNoneNode(name)

proc `+=`*(parent, child: NxNode) =
  discard

proc `[]=`*(parent: NxNode, child_name: string, i: int64) =
  let node = parent.addIntNode(i)
  node.setName(child_name)

proc `[]=`*(parent: NxNode, child_name: string, i: float64) =
  let node = parent.addRealNode(i)
  node.setName(child_name)

proc `[]=`*(parent: NxNode, child_name: string, v: array[0..1, int]) =
  let node = parent.addVectorNode(v[0].int32, v[1].int32)
  node.setName(child_name)

proc `[]=`*(parent: NxNode, child_name: string, v: VectorParameter) =
  let node = parent.addVectorNode(v.x.int32, v.y.int32)
  node.setName(child_name)

proc `[]=`*(parent: NxNode, child_name: string, s: string) =
  let node = parent.addStringNode(s)
  node.setName(child_name)

proc `[]=`*(parent: NxNode, child_name: string, b: BinaryParameter) =
  case b.kind:
  of ntBitmap:
    let node = parent.addBitmapNode(b.data)
    node.setName(child_name)
  of ntAudio:
    let node = parent.addAudioNode(b.data)
    node.setName(child_name)
  else: raiseAssert "square eq setter only allowed type of Bitmap and Audio."

proc `[]`*(nx: NxFile, name: string): NxNode =
  for node in nx.baseNode.children:
    if node.name == name:
      return node
  let n = new NilNode
  n.point = nx.baseNode
  n.expect = name
  return n

proc `[]`*(node: NxNode, name: string): NxNode =
  for i, child in node.children:
    if child.name == name:
      return child
  let n = new NilNode
  n.point = node
  n.expect = name
  return n

proc `/`*(node: NxNode, path: string): NxNode =
  result = node
  for name in path.split('/'):
    result = result[name]
    if result is NilNode:
      raiseAssert name ~ "not found in" ~ path

proc create*(node: NxNode): NxNode =
  if node is NilNode:
    let n = cast[NilNode](node)
    return n.point.addNoneNode(n.expect)
  elif not node.isNil:
    echo "Warning! if node is not a `NilNode`, it will be appended empty named None type node. please consider set name."
    return node.addNoneNode()
  else: echo "Warning! this node is nil"