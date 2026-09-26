#!/bin/bash
# usage: mcp.sh <tool> '<json args>'   (stateful streamable-HTTP session, id cached in /tmp/mcp-session)
URL=http://host.docker.internal:8792/mcp
H=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
sess=$(cat /tmp/mcp-session 2>/dev/null)
init() {
  sess=$(curl -s -m 30 -D - -o /dev/null -X POST $URL "${H[@]}" -d '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude","version":"1"}}}' | tr -d '\r' | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}')
  echo "$sess" > /tmp/mcp-session
  curl -s -m 10 -o /dev/null -X POST $URL "${H[@]}" -H "Mcp-Session-Id: $sess" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
}
[ -z "$sess" ] && init
out=$(curl -s -m 240 -X POST $URL "${H[@]}" -H "Mcp-Session-Id: $sess" -d "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":${2:-{\}}}}")
if echo "$out" | grep -qiE "session|Bad Request|not initialized" && ! echo "$out" | grep -q '"result"'; then init; out=$(curl -s -m 240 -X POST $URL "${H[@]}" -H "Mcp-Session-Id: $sess" -d "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":${2:-{\}}}}"); fi
echo "$out" | sed -n 's/^data: //p'
[ -z "$(echo "$out" | sed -n 's/^data: //p')" ] && echo "$out"
