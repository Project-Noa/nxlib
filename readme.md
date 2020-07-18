# nxlib.nim Documentation

# New Node

Creating a new `NxNode` is there are several ways. Let's start simple way first.

## Simple way

```nim
var nx: NxFile # must be initialized. it's a just sample
let base = nx.base_node
base += "new dir" # add named ntNone node
let new_dir = base["new dir"]
new_dir["ivalue"] = 45
new_dir["fvalue"] = 416.11
new_dir["familiy!"] = "nine"
new_dir["vector"] = (x: 40, y: 404) # or simply (40, 404), [40, 404]
new_dir["bitmap"] = (ntBitmap, "./image.png".open(fmRead).readAll)
new_dir["audio"] = (ntAudio, "./sound.wav".open(fmRead).readAll)
```

Those name explain itself how they to identity.

## Verbose Way

```nim
let i1 = base.addNoneNode() # no-named, basically name_id is 0
i1.setName("i have a name!")
discard i1.addNoneNode("named init") # same as above, but it init with given name
discard i1.addRealNode(1111.1111)
discard i1.addVectorNode(1, 2)
discard i1.addStringNode("hello")
discard i1.addBitmapNode("./image.png".open(fmRead).readAll)
discard i1.addAudioNode("./sound.wav".open(fmRead).readAll)
```

It is just little more verbose way. You can store variable by instantly

## Data Node

Nodes of `String`, `Bitmap` and `Audio` is a type of NxData. This nodes is associated with an offset table that is different from the itself node table.

But there is simple property point to Data object.

```jsx
let nxs: NxString = string.relative
let nxb: NxBitmap = bitmap.relative
let nxa: NxAudio = audio.relative
echo "string len: ", nxs.len
echo "bitmap len: ", nxb.len
echo "audio len: ", nxa.len
```

# Children

### Adding child

All nodes can have any children. As you seen before, this library provide simple way of to adding child.

```nim
nx.base_node.addNoneNode()
```

### Detach child

*it's a TODO api. not implemented*

```nim
var some_node: NxNode
some_node.detach()
```

It will set `nil` to `self.root`, `self.parent` and removed from `some_node.parent.children` array and `nx.nodes` with `self.children`. But object are still alive! It you want to destory them, just belive the nim's gc.

But it do not manipulate any of Data Tables. when you want to remove that too, here's another option. 

### Remove data

*it's a TODO api. not implemented*

```nim
some_node.detachWithData()
assert not some_node.relative.isNil # it's ok
```

But, this api only remove when those data nobody relatives with it.

### Moving alive node

*it's a TODO api. not implemented*

```nim
nx.base_node += some_node
```

It will reset parent and root and id. reassign `nx.nodes`

# Get node

It has two ways. first one is *Table (as known as Map, Dictionary or otherlikes)* getter.

At top of `New Node`, you can see like `base["new dir"]` this code.

```nim
# continue on Simple way codes...
let ival = new_dir["ivalue"]
echo ival.toString # print -> 45
echo ival.name # print "ivalue"
```

Second way is use `sequtils` module

```nim
import sequtils
let nodes = new_dir.children.filterIt(it.name == "ivalue")
```

Yes. *NX (PKG4)* is possible to exist on same named at the same level. It's useful in those situations.

# Why every name generate A new node?!

I think all data should be linked from nodes and a name (node) should be child of that node what they have named. Perhaps, you can redesign by your way.