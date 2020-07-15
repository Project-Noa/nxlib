# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import nxlib/node, nxlib/util, nxlib/read, nxlib/write

import nimpng, nimlz4, sequtils

proc dbg() =
  # [
  var nx = "./test.nx".newNxFile
  let i1 = nx.baseNode.addIntNode(0xCCCC)
  i1.setName("int1")
  let i2 = nx.baseNode.addIntNode(0xBBBB)
  i2.setName("int2")
  let i3 = nx.baseNode.addIntNode(0xAAAA)
  i3.setName("int3")
  let c1 = i3.addIntNode(0xDDDDDDDD'i64)
  c1.setName("int3-int")
  echo nx.nodes.len
  nx.save()
  # ]#
  # [

  
  let nx2 = openNxFile("./test.nx")
  
  for nxs in nx2.strings:
    echo nxs.data

when isMainModule: dbg()

export node, read, write, util