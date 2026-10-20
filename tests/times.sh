#!/bin/sh
# How long each test of a run took, from its log's first and last timestamps: tests/times.sh
# [results dir] (default: the latest run). Ends with the run's total.
d=${1:-$(ls -td "$(dirname "$0")"/../build/results/2* | head -1)}
total=0
for f in $(ls "$d"/T*.log | sort -t T -k 2 -n); do
	t=$(basename "$f" .log)
	s=$(head -1 "$f" | cut -c1-8); e=$(tail -1 "$f" | cut -c1-8)
	secs=$(echo "$s $e" | awk '{ split($1, a, ":"); split($2, b, ":"); print (b[1]*3600 + b[2]*60 + b[3]) - (a[1]*3600 + a[2]*60 + a[3]) }')
	r=$(grep -o "$t: \(PASS\|FAIL\)" "$f" | tail -1 | cut -d' ' -f2)
	printf '%-4s %-4s %3d:%02d\n' "$t" "${r:-?}" $((secs / 60)) $((secs % 60))
	total=$((total + secs))
done
printf 'total %d:%02d\n' $((total / 60)) $((total % 60))
