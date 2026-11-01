#!/usr/bin/env bash
# The last check before Temporal starts on this VM: refuse while another
# Temporal server uses the same database. Two servers on one database corrupt
# it, for example this VM and the cluster's Temporal during the cutover.
#
# A running Temporal server writes last_heartbeat in its cluster_membership
# rows every 10 to 15 seconds, in UTC. Any row written in the last 60 seconds
# means a server is alive, so the script exits 1 and lists them. record_expiry
# cannot be used: it is set 48 hours ahead. A database with no
# cluster_membership table is new, and nothing runs on it.
#
# temporal-server.service runs this before the schema step, so the schema is
# never changed under a running server, and again just before Temporal starts.
# The unit restarts every 10 seconds while it fails, so Temporal starts within
# a minute after the other server stops. This VM's own rows from a run that just stopped age out
# the same way. Stop the unit (systemctl stop temporal-server) to give up.
#
# The connection settings and the password come from /etc/temporal/temporal.env,
# read line by line, never sourced or printed.
set -euo pipefail

env_file="${TEMPORAL_ENV_FILE:-/etc/temporal/temporal.env}"
setting() { sed -n "s/^$1=//p" "$env_file" | head -n 1; }

PGHOST=$(setting SQL_HOST)
PGPORT=$(setting SQL_PORT)
PGUSER=$(setting SQL_USER)
PGPASSWORD=$(setting SQL_PASSWORD)
PGDATABASE=temporal
# The server's name and chain are checked against the system CAs. (psql 14 has
# no sslrootcert=system, so the bundle is named.)
PGSSLMODE=verify-full
PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt
PGCONNECT_TIMEOUT=10
export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE PGSSLMODE PGSSLROOTCERT PGCONNECT_TIMEOUT

query() { psql -X -q -t -A -v ON_ERROR_STOP=1 -c "$1"; }

# Each query result goes to a variable first: set -e stops the script when
# psql fails there, so an unreachable database never counts as a free one.
has_table=$(query "select to_regclass('public.cluster_membership') is not null")
if [ "$has_table" != "t" ]; then
  echo "no cluster_membership table: a new database, no other Temporal uses it"
  exit 0
fi

live=$(query "select rpc_address || ':' || rpc_port::text || ' role ' || role::text || ' last heartbeat ' || last_heartbeat::text
  from cluster_membership
  where last_heartbeat > (now() at time zone 'utc') - interval '60 seconds'
  order by last_heartbeat desc")

if [ -n "$live" ]; then
  echo "not starting Temporal: these members of another Temporal wrote a heartbeat in the last 60 seconds (UTC):"
  echo "$live"
  exit 1
fi

echo "no Temporal member wrote a heartbeat in the last 60 seconds"
