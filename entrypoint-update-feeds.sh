#!/usr/bin/env bash
# Entrypoint wrapper for traust-cli-toolkit-plus-feeds.
#
# Refreshes baked vulnerability databases via `traust-cli feeds update`
# before exec-ing the requested command.  The feeds update command fails
# open: any error is logged and the baked databases are used as-is.
#
# Set SKIP_FEED_UPDATE=1 to bypass (air-gapped deployments, CI caching).
set -u

if [ "${SKIP_FEED_UPDATE:-0}" != "1" ]; then
    timeout "${FEED_UPDATE_TIMEOUT:-120}" \
        /usr/local/bin/traust-cli feeds update \
        --max-age "${FEED_MAX_AGE:-120h}" >&2 &
    child=$!
    signalled=0
    # This script is PID 1, and a shell does not relay signals to its
    # children: without this trap, `podman stop`/ctrl-c would wait out the
    # whole FEED_UPDATE_TIMEOUT instead of interrupting the refresh.
    trap 'signalled=1; kill -TERM "${child}" 2>/dev/null' TERM INT
    # The update fails open (any error is logged, baked DBs are used as-is),
    # so a non-zero or killed child must not abort the run.
    wait "${child}" || true
    # A stop request that interrupted the refresh must terminate the
    # container, not fall through and launch the workload being stopped.
    [ "$signalled" = 1 ] && exit 143
fi

exec /usr/local/bin/traust-cli "$@"
