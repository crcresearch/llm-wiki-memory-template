# Integration test: drives the multi-agent wiki write-protocol prototype
# scenarios from the harness. Each prototype scenario is reported as a
# single harness assertion. The prototype lives independently at
# scripts/multi-agent-write-protocol-proto/ and remains runnable
# standalone via that directory's run-all.sh.
#
# Each scenario manages its own sandbox (via the prototype's sandbox.sh),
# so the harness's $SANDBOX is not used here.

PROTO_DIR="$(cd "$HERE/../multi-agent-write-protocol-proto" && pwd)"

if [ ! -d "$PROTO_DIR/scenarios" ]; then
    echo "  protocol prototype not found at $PROTO_DIR; skipping"
    skip "wiki-write-protocol: prototype directory missing" "$PROTO_DIR not found"
    return
fi

for scenario_script in "$PROTO_DIR"/scenarios/*/run.sh; do
    name=$(basename "$(dirname "$scenario_script")")
    log="/tmp/wiki-write-protocol-${name}.log"
    if bash "$scenario_script" > "$log" 2>&1; then
        assert "wiki-write-protocol/$name" "true"
    else
        echo "    (scenario log at $log; last 10 lines below)"
        tail -10 "$log" 2>/dev/null | sed 's/^/    /'
        assert "wiki-write-protocol/$name" "false"
    fi
done
