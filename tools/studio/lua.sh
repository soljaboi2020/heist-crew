#!/bin/bash
# usage: lua.sh <Server|Client|Edit> <file-with-luau>
SID=1f19ff1c-7fdd-4bae-b9f5-735997b0b186
python3 - "$1" "$2" <<'PY' > /tmp/lua_req.json
import json,sys
print(json.dumps({"studio_id":"1f19ff1c-7fdd-4bae-b9f5-735997b0b186","datamodel_type":sys.argv[1],"code":open(sys.argv[2]).read()}))
PY
"$(dirname "$0")/mcp.sh" execute_luau "$(cat /tmp/lua_req.json)" | python3 -c "import json,sys; d=json.load(sys.stdin); [print(c.get('text','')[:6000]) for c in d.get('result',{}).get('content',[])]; print(d.get('error',''))"
