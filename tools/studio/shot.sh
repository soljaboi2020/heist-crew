#!/bin/bash
# usage: shot.sh <outfile> [extra json args without braces]
SID=1f19ff1c-7fdd-4bae-b9f5-735997b0b186
"$(dirname "$0")/mcp.sh" screen_capture "{\"studio_id\":\"$SID\"${2:+,$2}}" > /tmp/shot.json
python3 - "$1" <<'PY'
import json,sys,base64
d=json.load(open('/tmp/shot.json'))
for c in d.get('result',{}).get('content',[]):
    if c.get('type')=='image':
        open(sys.argv[1],'wb').write(base64.b64decode(c['data'])); print('saved',sys.argv[1],c.get('mimeType'))
    elif c.get('type')=='text': print('text:',c['text'][:300])
if 'error' in d: print(d['error'])
PY
