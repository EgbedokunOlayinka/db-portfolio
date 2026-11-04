# Wavers University — Portfolio 2: summarise repeated EXPLAIN (ANALYZE, BUFFERS) runs
#
# Input: several runs of a plan script, one after another; each query's plan
# follows a label line "=== Qn. ...". For each query it prints the median of
# the runs for:
#   plan_ms   planning time
#   exec_ms   execution time
#   total_ms  planning + execution (what one call costs without a prepared plan)
#   buffers   buffer accesses of the whole query: the top plan node's
#             "Buffers: shared hit=H read=R", as H + R. A page visited
#             twice counts twice, so this measures work, not distinct pages.
# Usage: awk -f Olayinka_Egbedokun_plan_summary.awk plans.txt

/^=== Q[0-9]+S?\./ { q = $2; sub(/\.$/, "", q); if (!(q in seen)) { seen[q] = 1; order[++nq] = q }; top = 1; next }
# The top node is the first plan line after the label; its Buffers line (if
# any) comes before the first child ("->") or the Planning section.
top && /->|Planning/ { top = 0 }
top && /Buffers: shared/ {
    b = $0; sub(/,.*/, "", b); h = 0; r = 0
    if (match(b, /hit=[0-9]+/))  h = substr(b, RSTART + 4, RLENGTH - 4)
    if (match(b, /read=[0-9]+/)) r = substr(b, RSTART + 5, RLENGTH - 5)
    buf[q, ++nb[q]] = h + r; top = 0
}
/Planning Time:/  { pl[q, ++np[q]] = $3 }
/Execution Time:/ { ex[q, ++ne[q]] = $3; to[q, ne[q]] = $3 + pl[q, ne[q]] }

function median(arr, key, n,    i, j, t, a) {
    for (i = 1; i <= n; i++) a[i] = arr[key, i]
    for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j > 0 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t }
    return (n % 2) ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
}
END {
    printf "%-5s %4s %10s %10s %10s %9s\n", "query", "runs", "plan_ms", "exec_ms", "total_ms", "buffers"
    for (i = 1; i <= nq; i++) {
        q = order[i]
        printf "%-5s %4d %10.3f %10.3f %10.3f %9d\n", q, ne[q], median(pl, q, np[q]), median(ex, q, ne[q]), median(to, q, ne[q]), median(buf, q, nb[q])
    }
}
