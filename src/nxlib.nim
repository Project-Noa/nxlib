# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import nxlib/node
import streams, memfiles

proc readNode(fs: MemMapFileStream): NxNode =
  result.new
  result.name_id = fs.readUint32
  result.first_id = fs.readUint32
  result.children_count = fs.readUint16
  result.kind = fs.readUint16.toNxType
  if result.kind != ntNone:
    result.data = array[8, uint8].create()
    discard fs.readData(result.data, 8)

proc readHeader(fs: MemMapFileStream): NxHeader =
  result.new
  result.magic = fs.readStr(4)

  assert result.magic == "PKG4"

  result.node_count = fs.readUint32
  
  for i in 0..result.node_count:
    var node = fs.readNode()
    echo "id: ", node.name_id, ", first: ", node.first_id, ", children count: ", node.children_count, ", kind: ", node.kind

proc openNxFile*(path: string, fm: FileMode = fmRead): NxFile =
  result.new
  
  let fs = path.newMemMapFileStream(fm)
  result.file = fs

  result.header = fs.readHeader
  
  echo "done"


when isMainModule:
  discard openNxFile("./Character.nx")
  