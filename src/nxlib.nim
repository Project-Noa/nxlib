# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import nxlib/node, nxlib/util, nxlib/read, nxlib/write

import nimpng, nimlz4, sequtils
proc dbg() =
  # [
  var nx = "./test.nx".newNxFile
  let base = nx << "" # base node 
  # 0

  echo "base id: " & $base.id & ", " & base.name
  
  let character = newNxNone() # 1
  base["Character"] = character

  echo "character id: " & $character.id & ", " & character.name

  # 2
  let skin0 = newNxNone() # 3
  character["0002000.img"] = skin0
  skin0["z"] = newNxInt(1)

  echo "skin0 id: " & $skin0.id & ", " & skin0.name

  # 4
  let child = newNxInt(45)
  base["child"] = child

  let nxf = newNxReal(416.11)
  base["float"] = nxf

  let nxs = nx.newNxNodeString("nine")
  base["family"] = nxs

  let nxv = newNxVector(40, 404)
  base["vector"] = nxv

  let png = "./80038746_p0.png".open(fmRead)
  let nxb = nx.newNxNodeBitmap(png.readAll)
  base["bitmap"] = nxb

  let wav = "./bang.wav".open(fmRead)
  let nxa = nx.newNxNodeAudio(wav.readAll)
  base["audio"] = nxa

  nx.save()
  # ]#
  # [
  let nx2 = openNxFile("./test.nx")
  for node in nx2.nodes:
    echo node.children.mapIt(it.id), ": ", node.name, " (", node.name_id, ")"
  for nxs in nx.strings:
    echo nxs.toString
  # ]#

when isMainModule: dbg()

export node, read, write, util