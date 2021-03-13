#!/usr/bin/env sh

# build as static c library
nim cpp -d:exportClib --header --noMain --app:staticLib ./nxlib.nim

if [ -f "libnx.a" ] ; then
  rm libnx.a
fi

# change name
mv libnxlib.a libnx.a