#!/usr/bin/env sh\

if [ -f "nxlib" ] ; then
  rm nxlib
fi

# build as static c library
nim cpp -d:exportClib --header --noMain --app:staticLib src/nxlib.nim

if [ -f "libnx.a" ] ; then
  rm libnx.a
fi

# change name
mv nxlib libnx.a