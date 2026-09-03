#!/bin/bash -ex
moon update && rm -rf _build .mooncakes

# Upgrade every third-party dependency to its latest published version.
# Skips this repo's own module family (versions that track the local package).
if [ -f moon.mod ]; then
  SELF=$(awk -F'"' '/^name = /{print $2}' moon.mod)
elif [ -f moon.mod.json ]; then
  SELF=$(python3 -c "import json;print(json.load(open('moon.mod.json')).get('name',''))" 2>/dev/null || true)
else
  SELF=""
fi
find . -path '*/.mooncakes' -prune -o -path '*/_build' -prune -o -path '*/target' -prune -o -type f \( -name moon.mod -o -name moon.mod.json \) -print0 2>/dev/null | while IFS= read -r -d '' m; do
  dir=$(dirname "$m")
  if [ "${m##*/}" = moon.mod.json ]; then
    deps=$(python3 -c "import json,sys
d=json.load(open(sys.argv[1])).get('deps',{})
[print(k) for k in d]" "$m" 2>/dev/null)
  else
    deps=$(awk '/^import \{/,/^\}/' "$m" | sed -n 's/.*"\([^"]*\)".*/\1/p' | sed -E 's/@.*//')
  fi
  for dep in $deps; do
    case "$dep" in
      "$SELF"*) continue ;;
      "") continue ;;
    esac
    (cd "$dir" && moon add --upgrade "$dep" >/dev/null 2>&1 || true)
  done
done

moon fmt && moon info
moon test -j 12 --target all
