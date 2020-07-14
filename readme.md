# preview

```nim
  var nx = "./test.nx".newNxFile
  # base node
  # `<<` add given string to string node and set to None type.
  let base: NxNode = nx << ""
  
  let child: NxNode = newNxInt(45)
  base["child"] = child # parent[CHILD_NAME] = child

  let nxf: NxNode = newNxReal(416.11)
  base["float"] = nxf

  let nxs: NxNode = newNxNodeString("nine", nx)
  base["family"] = nxs

  let nxv: NxNode = newNxVector(40, 404)
  base["vector"] = nxv

  let png: File = "./good_image.png".open(fmRead)
  let nxb: NxNode = nx.newNxNodeBitmap(png.readAll)
  base["bitmap"] = nxb

  let wav: File = "./bang.wav".open(fmRead)
  let nxa: NxNode = nx.newNxNodeAudio(wav.readAll)
  base["audio"] = nxa

  nx.save()

  let nx2 = openNxFile("./test.nx")
  for nxs in nx2.strings:
    # nxs is [NxString]
    echo nxs.toString
  for nxb in nx2.bitmaps:
    # nxb is [NxBitmap]
    nxb.decode() # bitmap need to be decoded
    echo nxb.png.width, ", ", nxb.png.height
  for nxa in nx2.audios:
    let
      data = mxa.data
      length = data.len
    let cs = cm_new_source_from_mem(data, length)
    echo cs.getLength
```
