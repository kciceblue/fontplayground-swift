#!/bin/sh
set -eu
scenario=${FAKE_SCENARIO:-hello_ok}
command=$1
if [ "$scenario" = early_exit ] && [ "$command" != hello ]; then exit 3; fi
request=$(cat)
if [ -n "${FAKE_RECORD:-}" ]; then
  printf 'argv:%s\ntmpdir:%s\nstdin:%s\n' "$command" "${TMPDIR:-}" "$request" >> "$FAKE_RECORD"
fi
emit_hello_ok() {
cat <<'JSON'
{"protocol":1,"type":"hello","fpengine_version":"0.1.0","python":"3.12.14","fonttools":"4.66.0","unicode_version":"18.0.0","platform":"darwin-arm64","capabilities":["hello","scan","forge","forge.expect"],"face_reader_version":4}
{"protocol":1,"type":"result","command":"hello"}
JSON
}
emit_scan_ok() {
cat <<'JSON'
{"protocol":1,"type":"progress","stage":"scan","fraction":0.0,"done":0,"total":4}
{"protocol":1,"type":"face","face":{"path":"/fonts/FixtureSans-Regular.ttf","index":0,"size":9776,"mtime":1790000000.0,"family":"Fixture Sans","style":"Regular","full_name":"Fixture Sans Regular","postscript_name":null,"local_names":[],"outline":"glyf","is_collection":false,"is_variable":false,"axes":[],"weight_class":400,"italic":false,"upem":1000,"glyph_count":241,"coverage":[[32,126],[160,255],[913,929],[931,937],[945,969]],"group_counts":{"latin":191,"greek":49},"embedding":"installable","fs_type":0,"has_color":false,"supported":true,"unsupported_reason":null,"hidden":false,"suspicious_coverage":false,"ot_scripts":{"gsub":[],"gpos":[]},"aat":{"morx":false,"kerx":false,"kern_v1":false,"trak":false},"shapes_groups":[],"licence":{"class":"unknown","vendor_id":"????","notice":null},"has_os2":true,"is_forged":false,"font_revision":"1.000","unshaped":[]}}
{"protocol":1,"type":"face","face":{"path":"/fonts/FixtureSerif.ttc","index":0,"size":4604,"mtime":1790000000.0,"family":"Fixture Serif","style":"Regular","full_name":"Fixture Serif Regular","postscript_name":null,"local_names":[],"outline":"glyf","is_collection":true,"is_variable":false,"axes":[],"weight_class":400,"italic":false,"upem":1000,"glyph_count":96,"coverage":[[32,126]],"group_counts":{"latin":95},"embedding":"installable","fs_type":0,"has_color":false,"supported":true,"unsupported_reason":null,"hidden":false,"suspicious_coverage":false,"ot_scripts":{"gsub":[],"gpos":[]},"aat":{"morx":false,"kerx":false,"kern_v1":false,"trak":false},"shapes_groups":[],"licence":{"class":"unknown","vendor_id":"????","notice":null},"has_os2":true,"is_forged":false,"font_revision":"1.000","unshaped":[]}}
{"protocol":1,"type":"face","face":{"path":"/fonts/FixtureSerif.ttc","index":1,"size":4604,"mtime":1790000000.0,"family":"Fixture Serif","style":"Italic","full_name":"Fixture Serif Italic","postscript_name":null,"local_names":[],"outline":"glyf","is_collection":true,"is_variable":false,"axes":[],"weight_class":400,"italic":false,"upem":1000,"glyph_count":96,"coverage":[[32,126]],"group_counts":{"latin":95},"embedding":"installable","fs_type":0,"has_color":false,"supported":true,"unsupported_reason":null,"hidden":false,"suspicious_coverage":false,"ot_scripts":{"gsub":[],"gpos":[]},"aat":{"morx":false,"kerx":false,"kern_v1":false,"trak":false},"shapes_groups":[],"licence":{"class":"unknown","vendor_id":"????","notice":null},"has_os2":true,"is_forged":false,"font_revision":"1.000","unshaped":[]}}
{"protocol":1,"type":"file_error","path":"/fonts/NotAFont.ttf","code":"unreadable","message":"Not a font file fontTools can read (TTLibError: Not a TrueType or OpenType font (bad sfntVersion))."}
{"protocol":1,"type":"file_error","path":"/fonts/Missing.ttf","code":"not_found","message":"File not found."}
{"protocol":1,"type":"progress","stage":"scan","fraction":1.0,"done":4,"total":4}
{"protocol":1,"type":"result","command":"scan","summary":{"files":4,"faces":3,"file_errors":2,"duplicates":0}}
JSON
}
emit_forge_ok() {
cat <<'JSON'
{"protocol":1,"type":"progress","stage":"validate","fraction":0.0}
{"protocol":1,"type":"progress","stage":"plan","fraction":0.0}
{"protocol":1,"type":"progress","stage":"prepare","fraction":0.05,"material_index":0}
{"protocol":1,"type":"progress","stage":"prepare","fraction":0.35,"material_index":1}
{"protocol":1,"type":"progress","stage":"merge","fraction":0.7}
{"protocol":1,"type":"progress","stage":"finish","fraction":0.85}
{"protocol":1,"type":"progress","stage":"verify","fraction":0.95}
{"protocol":1,"type":"progress","stage":"done","fraction":1.0}
{"protocol":1,"type":"result","command":"forge","report":{"output_path":"/builds/Forged.ttf","family_name":"Fixture Forged","style_name":"Regular","postscript_name":"FixtureForgedFPd7bbac39-Regular","full_name":"Fixture Forged Regular","total_codepoints":3650,"total_glyphs":3651,"fs_type":0,"materials":[{"name":"Fixture Sans Regular","path":"/fonts/FixtureSans-Regular.ttf","index":0,"codepoints":240,"groups":["latin","greek"],"warnings":[]},{"name":"Fixture CJK Regular","path":"/fonts/FixtureCJK-Regular.otf","index":0,"codepoints":3410,"groups":["kana","han","cjk_symbols"],"warnings":[]}],"issues":[],"licence_notes":[],"warnings":[],"duration_s":1.234}}
JSON
}
emit_forge_error() {
cat <<'JSON'
{"protocol":1,"type":"progress","stage":"validate","fraction":0.0}
{"protocol":1,"type":"error","code":"stale_material","stage":"validate","material_index":1,"message":"/fonts/FixtureCJK-Regular.otf changed since it was scanned (size 81349 → 81348).","detail":null}
JSON
}
wait_for_term() {
  sleep 60 >/dev/null 2>&1 & sleeper=$!
  trap 'printf "TERM\n" >> "${FAKE_RECORD:-/dev/null}"; kill "$sleeper" 2>/dev/null || :; exit 143' TERM
  if [ "${1:-}" = progress ]; then progress; fi
  wait "$sleeper"
}
progress() {
  stage=$command
  if [ "$command" = forge ]; then stage=validate; fi
  printf '{"protocol":1,"type":"progress","stage":"%s","fraction":0,"done":0,"total":3}\n' "$stage"
}
if [ "$command" = hello ]; then
  case "$scenario" in
    hello_v2) emit_hello_ok | sed 's/"protocol":1/"protocol":2/g'; exit 0;;
    hello_missing_capability) emit_hello_ok | sed 's/"scan",//'; exit 0;;
    hello_garbage) printf 'not json\n'; exit 0;;
    hello_slow) wait_for_term; exit 0;;
    stderr_flood|stderr_flood_large)
      blocks=1024
      if [ "$scenario" = stderr_flood_large ]; then blocks=4096; fi
      dd if=/dev/zero bs=1024 count="$blocks" 2>/dev/null | tr '\000' x >&2;;
    unknown_type) printf '{"protocol":1,"type":"future_thing"}\n';;
  esac
  emit_hello_ok
  exit 0
fi
case "$scenario" in
  scan_ok) emit_scan_ok;;
  forge_ok) emit_forge_ok;;
  forge_error) emit_forge_error; exit 3;;
  split)
    printf '{"protocol":1,'; sleep 0.1
    printf '"type":"progress",'; sleep 0.1
    printf '"stage":"scan","fraction":0,"done":0,"total":2}\n'
    printf '%s\n%s\n' '{"protocol":1,"type":"progress","stage":"scan","fraction":0.5,"done":1,"total":2}' '{"protocol":1,"type":"progress","stage":"scan","fraction":1,"done":2,"total":2}'
    printf '{"protocol":1,"type":"result","command":"scan","summary":{"files":2,"faces":0,"file_errors":0,"duplicates":0}}\n';;
  big_line)
    printf '{"protocol":1,"type":"face","face":{"path":"/fonts/big.ttf","index":0,"family":"Big","style":"Regular","coverage":[[65,65]],"local_names":["'
    dd if=/dev/zero bs=1024 count=2048 2>/dev/null | tr '\000' x
    printf '"]}}\n{"protocol":1,"type":"result","command":"scan","summary":{"files":1,"faces":1,"file_errors":0,"duplicates":0}}\n';;
  garbage) printf 'not json\n';;
  no_terminal) progress;;
  truncated) printf '{"protocol":1';;
  crash) printf 'fake: about to crash\n' >&2; kill -SEGV $$;;
  slow) wait_for_term progress;;
  ignore_term)
    trap '' TERM
    mkdir -p "$TMPDIR/fpengine-$$-x" "$FAKE_OUTDIR"
    : > "$FAKE_OUTDIR/.fpengine-$$-x.partial.ttf"
    progress
    i=0; while [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done;;
  interrupted) exit 143;;
  result_linger) emit_scan_ok; wait_for_term;;
  result_nonzero) emit_scan_ok; printf 'not json\n'; exit 3;;
  idle_reset)
    i=0
    while [ "$i" -lt 4 ]; do
      printf '{"protocol":1,"type":"future_thing"}\n'
      sleep 0.15
      i=$((i+1))
    done
    emit_scan_ok;;
  inherited_pipe)
    # The grandchild keeps stdout open but closes every other inherited descriptor, so only the stdout pipe
    # delays EOF after the helper exits.
    bash -c 'for f in /dev/fd/*; do n=${f##*/}; if [ "$n" -gt 2 ]; then eval "exec $n>&-" 2>/dev/null; fi; done
      exec sleep 2' &
    printf '{"protocol":1'; exit 0;;
  *) printf 'unknown fake scenario: %s\n' "$scenario" >&2; exit 4;;
esac
