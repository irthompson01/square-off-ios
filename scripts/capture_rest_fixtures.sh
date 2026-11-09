#!/bin/zsh
# Captures REST responses from the local docker server (2026-11 contract: player sessions) as
# fixtures for SquareOffNetTests. Uses the seeded test account `contract_ios` plus a fresh guest.
# Usage: scripts/capture_rest_fixtures.sh [https://localhost:8002/api]
# curl keeps no cookies here, which matters: the server reads its session cookie before the
# bearer header, and create_guest sets one.
set -euo pipefail
API=${1:-https://localhost:8002/api}
OUT=$(cd "$(dirname "$0")/.." && pwd)/Packages/SquareOffKit/Tests/SquareOffNetTests/Fixtures
C() { curl -sk -m 20 "$@"; }
save() { python3 -m json.tool > "$OUT/$1.json"; echo "  $1.json"; }
jsonkey() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

echo "guest session"
GUEST_JSON=$(C -X POST "$API/create_guest" -H 'Content-Type: application/json' -d '{"name":"Guest","color":"#0583D2"}')
echo "$GUEST_JSON" | save create_guest_response
GUEST_ID=$(echo "$GUEST_JSON" | jsonkey '["player_id"]')
GUEST_TOKEN=$(echo "$GUEST_JSON" | jsonkey '["access_token"]')
G="Authorization: Bearer $GUEST_TOKEN"

echo "user session"
USER_TOKEN=$(C -X POST "$API/login?client=ios" -H 'Content-Type: application/json' -d '{"email_or_username":"contract_ios","password":"contract-pass-123"}' | jsonkey '["access_token"]')
U="Authorization: Bearer $USER_TOKEN"
USER_ID=$(C "$API/profile" -H "$U" | jsonkey '["id"]')

echo "cpu definitions"
for t in max-min-plus grandmaster impossible; do
  C "$API/cpu_player/$t" -H "$G" | save "cpu_player_${t//-/_}"
done
CPU_ID=$(C "$API/cpu_player/random" -H "$G" | jsonkey '["id"]')

echo "start: guest vs CPU, user vs CPU, pass & play"
start() { C -X POST "$API/start" -H 'Content-Type: application/json' -H "$1" -d "$2"; }
cpu_seat() { echo "{\"id\":2,\"name\":\"CPU (Random)\",\"color\":\"#FF3131\",\"playerId\":\"$CPU_ID\",\"isCPU\":true,\"cpuType\":\"random\"}"; }
start "$G" "{\"board_size\":8,\"timer\":0,\"players\":[{\"id\":1,\"name\":\"Player 1\",\"color\":\"#0583D2\",\"playerId\":\"$GUEST_ID\",\"isCPU\":false,\"cpuType\":null},$(cpu_seat)],\"type\":\"local\",\"is_cpu\":true,\"cpu_type\":\"random\"}" | save start_game_response
USER_START=$(start "$U" "{\"board_size\":8,\"timer\":20,\"players\":[{\"id\":1,\"name\":\"contract_ios\",\"color\":\"#0583D2\",\"playerId\":\"$USER_ID\",\"isCPU\":false,\"cpuType\":null},$(cpu_seat)],\"type\":\"local\",\"is_cpu\":true,\"cpu_type\":\"random\"}")
echo "$USER_START" | save start_game_response_user
USER_GAME=$(echo "$USER_START" | jsonkey '["game_id"]')
start "$G" "{\"board_size\":6,\"timer\":0,\"players\":[{\"id\":1,\"name\":\"Player 1\",\"color\":\"#0583D2\",\"playerId\":null,\"isCPU\":false,\"cpuType\":null},{\"id\":2,\"name\":\"Player 2\",\"color\":\"#FF3131\",\"playerId\":null,\"isCPU\":false,\"cpuType\":null},{\"id\":3,\"name\":\"Player 3\",\"color\":\"#50C878\",\"playerId\":null,\"isCPU\":false,\"cpuType\":null}],\"type\":\"local\",\"is_cpu\":false,\"cpu_type\":null}" | save start_game_pass_and_play

echo "cpu_move: an engine tier on a server without the engine (fallback)"
python3 - <<'PY' > /tmp/cpu_move_req.json
import json
board = [[None]*8 for _ in range(8)]; board[0][0] = {"id": 1}
cpu = {"id": 2, "name": "CPU (Impossible)", "isCPU": True, "cpuType": "impossible", "fillStyle": "#FF3131", "currentScore": 0, "currentMultiplier": 1, "squares": [], "diamonds": []}
me = {"id": 1, "name": "Player 1", "isCPU": False, "fillStyle": "#0583D2", "currentScore": 0, "currentMultiplier": 1, "squares": [], "diamonds": []}
print(json.dumps({"game_id": 1, "board_state": board, "current_player": cpu, "game_players": [me, cpu], "cpu_type": "impossible", "timer": None}))
PY
C -X POST "$API/cpu_move" -H 'Content-Type: application/json' -H "$G" -d @/tmp/cpu_move_req.json | save cpu_move_fallback_response
rm -f /tmp/cpu_move_req.json

echo "sign-up and verification"
STAMP=$(date +%s)
C -X POST "$API/register" -H 'Content-Type: application/json' -d "{\"username\":\"fixture_$STAMP\",\"email\":\"fixture+$STAMP@example.org\",\"password\":\"longenough1\",\"website\":\"\",\"registered\":true}" | save register_response
C -X POST "$API/login?client=ios" -H 'Content-Type: application/json' -d "{\"email_or_username\":\"fixture_$STAMP\",\"password\":\"longenough1\"}" | save error_email_unverified
C -X POST "$API/verify-email/resend" -H 'Content-Type: application/json' -d "{\"email\":\"fixture+$STAMP@example.org\"}" | save verify_email_resend_response
C -X POST "$API/verify-email" -H 'Content-Type: application/json' -d '{"token":"xxxxxxxxxxxxxxxxxxxxxxxx"}' | save error_verify_token_invalid

echo "session refusals"
C "$API/cpu_player/random" | save error_session_required
C -X POST "$API/create_guest" -H 'Content-Type: application/json' -H "$U" -d '{"name":"Guest","color":"#0583D2"}' | save error_already_signed_in
start "$G" "{\"board_size\":6,\"timer\":0,\"players\":[{\"id\":1,\"name\":\"Not me\",\"color\":\"#0583D2\",\"playerId\":\"$USER_ID\",\"isCPU\":false,\"cpuType\":null},$(cpu_seat)],\"type\":\"local\",\"is_cpu\":true,\"cpu_type\":\"random\"}" | save error_seat_not_yours
C -X PUT "$API/end" -H 'Content-Type: application/json' -H "$G" -d "{\"game_id\":$USER_GAME,\"winner_id\":\"\",\"scores\":[]}" | save error_not_a_player
C "$API/check-auth" -H "$G" | save error_account_required
echo "done"
