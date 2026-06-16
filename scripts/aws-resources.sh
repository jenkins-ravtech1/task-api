#!/usr/bin/env bash
# =============================================================================
# aws-resources.sh — snapshot your account's resources into a nice HTML page.
#
# Runs the Resource Groups Tagging API (the same data as
#   aws resourcegroupstaggingapi get-resources --region <r> --output table)
# but as JSON, then renders a searchable/sortable HTML dashboard and opens it.
#
# Usage:
#   ./scripts/aws-resources.sh                # region eu-central-1 (this project)
#   ./scripts/aws-resources.sh us-east-1      # another region (also shows many
#                                             #   global resources like IAM/S3)
#   OUT=mine.html ./scripts/aws-resources.sh  # choose the output file
#
# Notes:
#   * This API is REGIONAL and lists only resources that SUPPORT tagging.
#   * Uses your existing AWS CLI credentials. If you use SSO and the token has
#     expired, run `aws sso login` first.
#   * It also probes the app's /health on the running app instance(s) for LIVE
#     serving status. Tune with: APP_PORT (default 8080), APP_NAME (the instance
#     Name tag, default tasks-api-app), HEALTH_PATH (default /health).
# =============================================================================
set -euo pipefail

REGION="${1:-${AWS_REGION:-eu-central-1}}"
OUT="${OUT:-aws-resources.html}"

c_err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
c_info() { printf '\033[36m%s\033[0m\n' "$*"; }

command -v aws >/dev/null 2>&1 || { c_err "AWS CLI not found — install it: https://aws.amazon.com/cli/"; exit 1; }

ERRF="$(mktemp)"; trap 'rm -f "$ERRF"' EXIT

c_info "Checking AWS credentials…"
if ! ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>"$ERRF")"; then
  c_err "Could not authenticate to AWS."
  c_err "If you use SSO, run:  aws sso login"
  sed 's/^/  aws: /' "$ERRF" >&2 || true
  exit 1
fi
CALLER="$(aws sts get-caller-identity --query Arn --output text)"

c_info "Querying resources in ${REGION}…"
if ! RES_JSON="$(aws resourcegroupstaggingapi get-resources --region "$REGION" --output json 2>"$ERRF")"; then
  c_err "Query failed."
  sed 's/^/  aws: /' "$ERRF" >&2 || true
  exit 1
fi

# Count occurrences of ResourceARN (no jq dependency); tolerate zero matches.
COUNT="$(printf '%s' "$RES_JSON" | grep -o '"ResourceARN"' | wc -l | tr -d '[:space:]')" || COUNT=0
[ -n "$COUNT" ] || COUNT=0

# --- Live runtime state ------------------------------------------------------
# The tagging API lists what EXISTS, not what's RUNNING. Only a few services
# have a run-state, so we query those and build a "service|name -> state" map.
# Everything else is shown as "available" (present) by the HTML.
c_info "Checking runtime state (ec2 / lambda / dynamodb)…"
status_pairs=""
add_pair(){ if [ -n "${2:-}" ]; then status_pairs+="\"$1\":\"$2\","; fi; }

# EC2 instances → running / stopped / pending / …
EC2_RAW="$(aws ec2 describe-instances --region "$REGION" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text 2>/dev/null || true)"
while IFS=$'\t' read -r _id _st; do
  if [ -n "$_id" ]; then add_pair "ec2|$_id" "$_st"; fi
done <<< "$EC2_RAW"

# Lambda functions → Active / Inactive / Pending / Failed
LAMBDA_RAW="$(aws lambda list-functions --region "$REGION" \
  --query 'Functions[].[FunctionName,State]' --output text 2>/dev/null || true)"
while IFS=$'\t' read -r _n _st; do
  if [ -n "$_n" ]; then add_pair "lambda|$_n" "$_st"; fi
done <<< "$LAMBDA_RAW"

# DynamoDB tables → ACTIVE / CREATING / …  (TableStatus needs a per-table call)
DDB_TABLES="$(aws dynamodb list-tables --region "$REGION" --query 'TableNames[]' --output text 2>/dev/null || true)"
for _t in $DDB_TABLES; do
  _st="$(aws dynamodb describe-table --table-name "$_t" --region "$REGION" \
    --query 'Table.TableStatus' --output text 2>/dev/null || true)"
  add_pair "dynamodb|$_t" "$_st"
done

# EBS volumes → in-use (attached) / available (detached) / …  A volume that's
# been DELETED simply won't appear here, even though the tagging API may still
# list it — the HTML treats "missing from this list" as deleted/ghost.
EBS_RAW="$(aws ec2 describe-volumes --region "$REGION" \
  --query 'Volumes[].[VolumeId,State]' --output text 2>/dev/null || true)"
while IFS=$'\t' read -r _vid _st; do
  if [ -n "$_vid" ]; then add_pair "ec2|$_vid" "$_st"; fi
done <<< "$EBS_RAW"

STATUS_JSON="{${status_pairs%,}}"

# --- Live app health ---------------------------------------------------------
# "running" above only means the VM is on. This probes the app's /health on the
# running app instance(s) to say whether the API is actually SERVING.
APP_TAG="${APP_NAME:-tasks-api-app}"
HEALTH_PORT="${APP_PORT:-8080}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
c_info "Probing app health (${APP_TAG}:${HEALTH_PORT}${HEALTH_PATH})…"
health_items=""
APP_INSTANCES="$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=${APP_TAG}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress]' --output text 2>/dev/null || true)"
while IFS=$'\t' read -r _iid _ip; do
  if [ -z "$_iid" ]; then continue; fi
  if [ -z "$_ip" ] || [ "$_ip" = "None" ]; then
    health_items+="{\"id\":\"$_iid\",\"ip\":\"\",\"port\":$HEALTH_PORT,\"ok\":false,\"code\":\"no-public-ip\",\"status\":\"\",\"version\":\"\",\"t\":0},"
    continue
  fi
  # One curl captures body + status code + total time.
  _resp="$(curl -s -m 5 -w $'\n%{http_code}\n%{time_total}' "http://${_ip}:${HEALTH_PORT}${HEALTH_PATH}" 2>/dev/null || true)"
  _t="${_resp##*$'\n'}";  _rest="${_resp%$'\n'*}"
  _code="${_rest##*$'\n'}"; _body="${_rest%$'\n'*}"
  case "$_t" in ''|*[!0-9.]*) _t=0;; esac
  [ -n "$_code" ] || _code="000"
  _status="$(printf '%s' "$_body" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
  _version="$(printf '%s' "$_body" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
  _ok=false; [ "$_code" = "200" ] && _ok=true
  health_items+="{\"id\":\"$_iid\",\"ip\":\"$_ip\",\"port\":$HEALTH_PORT,\"ok\":$_ok,\"code\":\"$_code\",\"status\":\"$_status\",\"version\":\"$_version\",\"t\":$_t},"
done <<< "$APP_INSTANCES"
HEALTH_JSON="[${health_items%,}]"

# Embed the blobs as base64 — sidesteps every quoting/`</script>` escaping issue.
DATA_B64="$(printf '%s' "$RES_JSON" | base64 | tr -d '\n')"
STATUS_B64="$(printf '%s' "$STATUS_JSON" | base64 | tr -d '\n')"
HEALTH_B64="$(printf '%s' "$HEALTH_JSON" | base64 | tr -d '\n')"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

# ---- generate the HTML (static head, injected data, static app) -------------
{
cat <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AWS Resources</title>
<style>
:root{--navy:#1f2731;--navy2:#161c24;--orange:#ff9900;--ink:#e7ebf0;--muted:#8a94a3;--line:#2a313c;--bg:#0f141a;--card:#181d25;--chip:#222a34}
*{box-sizing:border-box}
html{color-scheme:dark}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:var(--ink);background:var(--bg)}
header.topbar{background:linear-gradient(180deg,var(--navy),var(--navy2));color:#fff;padding:16px 24px;display:flex;align-items:center;gap:16px;flex-wrap:wrap}
.topbar h1{font-size:17px;margin:0;font-weight:650;letter-spacing:.2px;display:flex;align-items:center;gap:9px}
.topbar .dot{color:var(--orange);font-size:12px}
.meta{margin-left:auto;display:flex;gap:18px;flex-wrap:wrap;font-size:12.5px;color:#c7d0db}
.meta b{color:#fff;font-weight:600}
.wrap{max-width:1200px;margin:0 auto;padding:22px 24px 50px}
.summary{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:16px}
.total{font-size:14px;color:var(--muted)}
.total b{font-size:22px;color:var(--ink);font-weight:700;margin-right:4px}
.chips{display:flex;gap:8px;flex-wrap:wrap}
.chip{cursor:pointer;border:1px solid var(--line);background:var(--card);border-radius:999px;padding:5px 12px;font-size:12.5px;display:flex;gap:7px;align-items:center;transition:.12s;color:var(--ink)}
.chip:hover{border-color:#3a434f}
.chip.active{background:var(--orange);color:#1a1205;border-color:var(--orange)}
.chip .n{background:var(--chip);color:var(--muted);border-radius:999px;padding:1px 7px;font-size:11px;font-weight:600}
.chip.active .n{background:rgba(0,0,0,.20);color:#1a1205}
.toolbar{display:flex;gap:12px;align-items:center;margin-bottom:14px}
.search{flex:1;display:flex;align-items:center;gap:9px;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 14px}
.search input{border:0;outline:0;font-size:14px;width:100%;background:transparent;color:var(--ink)}
.search input::placeholder{color:var(--muted)}
.search:focus-within{border-color:#3a434f}
.shown{font-size:12.5px;color:var(--muted);white-space:nowrap}
.toggle{display:inline-flex;align-items:center;gap:6px;font-size:12.5px;color:var(--muted);white-space:nowrap;cursor:pointer;user-select:none}
.toggle input{accent-color:var(--orange);cursor:pointer;margin:0}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden}
thead th{text-align:left;font-size:11.5px;text-transform:uppercase;letter-spacing:.6px;color:var(--muted);padding:11px 14px;border-bottom:1px solid var(--line);cursor:pointer;user-select:none;white-space:nowrap}
thead th.nosort{cursor:default}
thead th .arrow{opacity:.45;font-size:10px;margin-left:2px}
tbody td{padding:11px 14px;border-bottom:1px solid var(--line);font-size:13px;vertical-align:top}
tbody tr:last-child td{border-bottom:0}
tbody tr:hover{background:#1e242d}
.svc{font-weight:600}
.name{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12.5px;word-break:break-all}
.muted{color:var(--muted)}
.tags{display:flex;gap:5px;flex-wrap:wrap;max-width:300px}
.tag{background:var(--chip);border-radius:6px;padding:2px 7px;font-size:11px;color:#aeb8c6;white-space:nowrap}
.tag b{font-weight:600;color:var(--ink)}
code.arn{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;color:#9aa4b2;cursor:pointer;display:inline-block;max-width:360px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;vertical-align:bottom}
code.arn:hover{color:var(--orange)}
.state{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:600;padding:3px 9px;border-radius:999px;background:var(--chip);white-space:nowrap}
.sdot{width:7px;height:7px;border-radius:50%;flex:0 0 auto;background:#8a94a3}
.state-up{color:#3fb950} .state-up .sdot{background:#3fb950}
.state-ready{color:#58a6ff} .state-ready .sdot{background:#58a6ff}
.state-idle{color:#8a94a3} .state-idle .sdot{background:#8a94a3}
.state-pending{color:#d8a019} .state-pending .sdot{background:#d8a019}
.state-down{color:#f85149} .state-down .sdot{background:#f85149}
.state-unknown{color:#8a94a3} .state-unknown .sdot{background:#5a626d}
.state-gone{color:#6b7785;text-decoration:line-through} .state-gone .sdot{background:#46505e}
.runcount{display:inline-flex;align-items:center;gap:7px;font-size:13px;color:var(--ink);font-weight:600}
.legend{display:flex;gap:9px;flex-wrap:wrap;margin-bottom:14px}
.health{max-width:1200px;margin:16px auto 0;padding:0 24px;display:flex;flex-direction:column;gap:8px}
.hbanner{display:flex;align-items:center;gap:14px;padding:11px 16px;border-radius:10px;font-size:13px;border:1px solid;flex-wrap:wrap}
.hbanner.ok{background:rgba(63,185,80,.10);border-color:rgba(63,185,80,.35)}
.hbanner.down{background:rgba(248,81,73,.10);border-color:rgba(248,81,73,.35)}
.hbanner .lbl{font-weight:700;display:inline-flex;align-items:center;gap:7px}
.hbanner.ok .lbl{color:#3fb950}
.hbanner.down .lbl{color:#f85149}
.hbanner .mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--muted)}
.empty{text-align:center;padding:64px 20px;color:var(--muted)}
.empty h2{color:var(--ink);font-weight:600;margin:0 0 8px}
.toast{position:fixed;bottom:24px;left:50%;transform:translateX(-50%) translateY(20px);background:#2b3340;color:#fff;border:1px solid #3a434f;padding:9px 16px;border-radius:8px;font-size:13px;opacity:0;pointer-events:none;transition:.2s}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
footer{max-width:1200px;margin:0 auto;padding:0 24px 40px;color:var(--muted);font-size:12px;line-height:1.6}
footer code{background:var(--chip);padding:1px 6px;border-radius:5px}
</style>
</head>
<body>
<header class="topbar">
  <h1><span class="dot">&#9679;</span> AWS Resources</h1>
  <div class="meta">
    <span>Account <b id="m-account">&mdash;</b></span>
    <span>Region <b id="m-region">&mdash;</b></span>
    <span>Identity <b id="m-caller">&mdash;</b></span>
    <span>Generated <b id="m-time">&mdash;</b></span>
  </div>
</header>
<div class="health" id="health"></div>
<div class="wrap">
  <div class="summary">
    <div class="total"><b id="total">0</b>resources</div>
    <div class="runcount" id="runcount"></div>
    <div class="chips" id="chips"></div>
  </div>
  <div class="toolbar">
    <label class="search">
      <span class="muted">&#8981;</span>
      <input id="search" type="text" placeholder="Filter by name, service, type, ARN, or tag&hellip;" autofocus>
    </label>
    <label class="toggle"><input type="checkbox" id="hideGone" checked> Hide terminated / deleted</label>
    <span class="shown" id="shown"></span>
  </div>
  <div id="tableWrap">
    <table>
      <thead><tr>
        <th data-key="service">Service <span class="arrow">&#8597;</span></th>
        <th data-key="type">Type <span class="arrow">&#8597;</span></th>
        <th data-key="name">Name / ID <span class="arrow">&#8597;</span></th>
        <th data-key="state">State <span class="arrow">&#8597;</span></th>
        <th data-key="region">Region <span class="arrow">&#8597;</span></th>
        <th class="nosort">Tags</th>
        <th data-key="arn">ARN <span class="arrow">&#8597;</span></th>
      </tr></thead>
      <tbody id="rows"></tbody>
    </table>
  </div>
  <div class="empty" id="empty" style="display:none">
    <h2>No resources found</h2>
    <p>Nothing matched &mdash; or this region has no tag-supported resources.<br>
       Check you're scanning the right region and that your SSO session is active.</p>
  </div>
</div>
<footer>
  <div class="legend">
    <span class="state state-up"><span class="sdot"></span>running / active</span>
    <span class="state state-ready"><span class="sdot"></span>available</span>
    <span class="state state-pending"><span class="sdot"></span>updating</span>
    <span class="state state-down"><span class="sdot"></span>stopped / failed</span>
    <span class="state state-unknown"><span class="sdot"></span>not checked</span>
    <span class="state state-gone"><span class="sdot"></span>terminated / deleted</span>
  </div>
  Source: <code>aws resourcegroupstaggingapi get-resources</code> &middot; regional &middot; lists only resources that support tagging.<br>
  <b>State</b> is live &mdash; queried from EC2 / Lambda / DynamoDB. Services with no run-state (SQS, SNS, S3, ECR, IAM&hellip;) show <i>available</i> when present.<br>
  The banner above probes <code>/health</code> on the running app instance(s) &mdash; it's the definitive "is the API serving" check (tune with <code>APP_PORT</code> / <code>APP_NAME</code>).<br>
  Scan another region: <code>./scripts/aws-resources.sh us-east-1</code> (us-east-1 also surfaces many global resources such as IAM and CloudFront).
</footer>
<div class="toast" id="toast"></div>
<script>
HTML_HEAD

printf '  window.__META__ = { account: "%s", caller: "%s", region: "%s", generatedAt: "%s" };\n' \
  "$ACCOUNT" "$CALLER" "$REGION" "$TIMESTAMP"
printf '  window.__DATA_B64__ = "%s";\n' "$DATA_B64"
printf '  window.__STATUS_B64__ = "%s";\n' "$STATUS_B64"
printf '  window.__HEALTH_B64__ = "%s";\n' "$HEALTH_B64"

cat <<'HTML_BODY'
</script>
<script>
const META   = window.__META__ || {};
const raw    = decodeData(window.__DATA_B64__ || "");
const STATUS = decodeMap(window.__STATUS_B64__ || "");
const HEALTH = decodeArr(window.__HEALTH_B64__ || "");
const HEALTHBYID = {}; HEALTH.forEach(h => { HEALTHBYID[h.id] = h; });

function decodeData(b64){
  if(!b64) return {ResourceTagMappingList:[]};
  try{
    const bin = atob(b64);
    const bytes = Uint8Array.from(bin, c => c.charCodeAt(0));
    return JSON.parse(new TextDecoder("utf-8").decode(bytes));
  }catch(e){ console.error("decode failed", e); return {ResourceTagMappingList:[]}; }
}
function decodeMap(b64){
  if(!b64) return {};
  try{
    const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
    return JSON.parse(new TextDecoder("utf-8").decode(bytes)) || {};
  }catch(e){ return {}; }
}
function decodeArr(b64){
  if(!b64) return [];
  try{
    const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
    const v = JSON.parse(new TextDecoder("utf-8").decode(bytes));
    return Array.isArray(v) ? v : [];
  }catch(e){ return []; }
}

// Map a resource's live state to a label, colour class, and sort rank.
function statusFor(it){
  const rs = STATUS[it.service + "|" + it.name];
  const s = rs == null ? null : String(rs).toLowerCase();
  const B = (label, cls, rank) => ({label, cls, rank});
  if(it.service === "ec2"){
    if(it.type === "volume"){
      if(s === "in-use") return B("in-use","ready",2);
      if(s === "available") return B("detached","pending",1);   // orphan — still billing
      if(s === "creating" || s === "deleting") return B(s,"pending",1);
      if(s) return B(s,"idle",3);
      return B("deleted","gone",6);                             // not in describe-volumes → gone
    }
    if(it.type && it.type !== "instance") return B("available","ready",2);  // security-group, etc.
    if(s === "running"){
      const h = HEALTHBYID[it.name];           // did we probe /health on this box?
      if(h) return h.ok ? B("running · API up","up",0) : B("running · API down","down",-1);
      return B("running","up",0);
    }
    if(s === "pending" || s === "rebooting") return B(s,"pending",1);
    if(s === "stopping" || s === "shutting-down") return B(s,"pending",1);
    if(s === "stopped") return B("stopped","down",4);
    if(s === "terminated") return B("terminated","gone",6);     // ghost — already destroyed
    if(s) return B(s,"idle",3);
    return B("gone","gone",6);                                  // not in describe → terminated/purged
  }
  if(it.service === "lambda"){
    // Only actual functions have a run-state; event-source-mappings, layers, etc.
    // are just "present" — don't fake an "active" for them.
    if(it.type && it.type !== "function") return B("available","ready",2);
    if(s === null || s === "none" || s === "active") return B("active","up",0);
    if(s === "pending") return B("pending","pending",1);
    if(s === "inactive") return B("inactive","idle",3);
    if(s === "failed") return B("failed","down",4);
    return B(s,"idle",3);
  }
  if(it.service === "dynamodb"){
    if(s === "active") return B("active","up",0);
    if(s === "creating" || s === "updating") return B(s,"pending",1);
    if(s) return B(s,"down",4);
    return B("unknown","unknown",5);
  }
  const READY = new Set(["sqs","sns","s3","ecr","iam","logs","events","cloudwatch","kms","ssm","secretsmanager","sts","cloudfront","route53","apigateway","states","cloudformation","elasticloadbalancing","autoscaling"]);
  if(READY.has(it.service)) return B("available","ready",2);
  return B("—","unknown",5);
}

// arn:partition:service:region:account:resourcetype/name (or :name, or type:name)
function parseArn(arn){
  const p = String(arn).split(":");
  const service = p[2] || "", region = p[3] || "", account = p[4] || "";
  let rest = p.slice(5).join(":"), type = "", name = rest;
  if(rest.includes("/")){ const i = rest.indexOf("/"); type = rest.slice(0,i); name = rest.slice(i+1); }
  else if(rest.includes(":")){ const i = rest.indexOf(":"); type = rest.slice(0,i); name = rest.slice(i+1); }
  return {service, region, account, type, name};
}

const items = (raw.ResourceTagMappingList || []).map(r => {
  const a = parseArn(r.ResourceARN);
  const tags = (r.Tags || []).map(t => ({k:t.Key, v:t.Value}));
  return {
    arn: r.ResourceARN, ...a, tags,
    search: (r.ResourceARN + " " + a.service + " " + a.type + " " + a.name + " " +
             tags.map(t => t.k + " " + t.v).join(" ")).toLowerCase()
  };
});
items.forEach(it => {
  const s = statusFor(it);
  it.stateLabel = s.label; it.stateCls = s.cls; it.stateRank = s.rank;
  it.search += " " + s.label.toLowerCase();
});

const state = { q:"", svc:null, key:"service", dir:1, hideGone:true };
const $ = id => document.getElementById(id);

function view(){
  let v = items.filter(it =>
    (!state.svc || it.service === state.svc) &&
    (!state.q || it.search.includes(state.q)) &&
    (!state.hideGone || it.stateCls !== "gone"));
  v.sort((a,b) => {
    if(state.key === "state"){
      const d = (a.stateRank - b.stateRank) * state.dir;
      return d || a.service.localeCompare(b.service);
    }
    const x = String(a[state.key]||"").toLowerCase(), y = String(b[state.key]||"").toLowerCase();
    return x < y ? -state.dir : x > y ? state.dir : 0;
  });
  return v;
}

function td(text, cls){ const d = document.createElement("td"); if(cls) d.className = cls; d.textContent = text; return d; }

function renderRows(){
  const v = view(), tb = $("rows");
  tb.textContent = "";
  const ghosts = items.filter(i => i.stateCls === "gone").length;
  $("shown").textContent = `Showing ${v.length} of ${items.length}` +
    (state.hideGone && ghosts ? ` · ${ghosts} terminated/deleted hidden` : "");
  $("empty").style.display = v.length ? "none" : "block";
  $("tableWrap").style.display = v.length ? "block" : "none";
  for(const it of v){
    const tr = document.createElement("tr");
    tr.appendChild(td(it.service, "svc"));
    tr.appendChild(td(it.type || "—", it.type ? "" : "muted"));
    tr.appendChild(td(it.name || "—", "name"));
    const stTd = document.createElement("td");
    const badge = document.createElement("span"); badge.className = "state state-" + it.stateCls;
    const sdot = document.createElement("span"); sdot.className = "sdot";
    badge.appendChild(sdot); badge.appendChild(document.createTextNode(it.stateLabel));
    stTd.appendChild(badge); tr.appendChild(stTd);
    tr.appendChild(td(it.region || "global", "muted"));
    const tt = document.createElement("td");
    if(!it.tags.length){ tt.className = "muted"; tt.textContent = "—"; }
    else{
      const box = document.createElement("div"); box.className = "tags";
      for(const t of it.tags){
        const sp = document.createElement("span"); sp.className = "tag";
        const b = document.createElement("b"); b.textContent = t.k; sp.appendChild(b);
        sp.appendChild(document.createTextNode("=" + (t.v || "")));
        box.appendChild(sp);
      }
      tt.appendChild(box);
    }
    tr.appendChild(tt);
    const at = document.createElement("td");
    const c = document.createElement("code"); c.className = "arn"; c.textContent = it.arn;
    c.title = "Click to copy\n" + it.arn; c.onclick = () => copy(it.arn);
    at.appendChild(c); tr.appendChild(at);
    tb.appendChild(tr);
  }
}

function renderChips(){
  const counts = {};
  for(const it of items) counts[it.service] = (counts[it.service]||0) + 1;
  const arr = Object.entries(counts).sort((a,b) => b[1]-a[1] || a[0].localeCompare(b[0]));
  const box = $("chips"); box.textContent = "";
  for(const [svc,n] of arr){
    const c = document.createElement("button");
    c.className = "chip" + (state.svc === svc ? " active" : "");
    c.onclick = () => { state.svc = state.svc === svc ? null : svc; renderChips(); renderRows(); };
    const label = document.createElement("span"); label.textContent = svc;
    const num = document.createElement("span"); num.className = "n"; num.textContent = n;
    c.appendChild(label); c.appendChild(num); box.appendChild(c);
  }
}

function renderHealth(){
  const box = $("health"); box.textContent = "";
  for(const h of HEALTH){
    const div = document.createElement("div");
    div.className = "hbanner " + (h.ok ? "ok" : "down");
    const lbl = document.createElement("span"); lbl.className = "lbl";
    const dot = document.createElement("span"); dot.className = "sdot";
    dot.style.background = h.ok ? "#3fb950" : "#f85149";
    lbl.appendChild(dot);
    lbl.appendChild(document.createTextNode(h.ok ? "API healthy" : "API not responding"));
    div.appendChild(lbl);
    const url = document.createElement("span"); url.className = "mono";
    url.textContent = h.ip ? ("http://" + h.ip + ":" + h.port + "/health") : (h.id + " (no public IP)");
    div.appendChild(url);
    const bits = [];
    if(h.ok && h.status) bits.push(h.status);
    if(h.ok && h.version) bits.push("version " + String(h.version).slice(0, 12));
    if(h.ok && h.t) bits.push(Math.round(h.t * 1000) + " ms");
    if(!h.ok && h.code) bits.push(h.code === "000" ? "unreachable" : "HTTP " + h.code);
    for(const b of bits){ const s = document.createElement("span"); s.className = "mono"; s.textContent = b; div.appendChild(s); }
    box.appendChild(div);
  }
}

function updateArrows(){
  document.querySelectorAll("th[data-key]").forEach(th => {
    const a = th.querySelector(".arrow"); if(!a) return;
    a.textContent = th.dataset.key === state.key ? (state.dir > 0 ? "▲" : "▼") : "↕";
  });
}

function copy(text){
  const done = () => toast("Copied ARN");
  if(navigator.clipboard && navigator.clipboard.writeText)
    navigator.clipboard.writeText(text).then(done).catch(() => fallbackCopy(text, done));
  else fallbackCopy(text, done);
}
function fallbackCopy(text, cb){
  const ta = document.createElement("textarea"); ta.value = text;
  document.body.appendChild(ta); ta.select();
  try{ document.execCommand("copy"); }catch(e){}
  ta.remove(); cb && cb();
}
let toastT;
function toast(m){
  const el = $("toast"); el.textContent = m; el.classList.add("show");
  clearTimeout(toastT); toastT = setTimeout(() => el.classList.remove("show"), 1400);
}

// header meta
$("total").textContent = items.length;
const runningCount = items.filter(i => i.stateCls === "up").length;
const rc = $("runcount");
const rcDot = document.createElement("span"); rcDot.className = "sdot"; rcDot.style.background = "#3fb950";
rc.appendChild(rcDot); rc.appendChild(document.createTextNode(runningCount + " running / active"));
$("m-account").textContent = META.account || "—";
$("m-region").textContent  = META.region  || "—";
$("m-caller").textContent  = (META.caller || "—").split("/").pop();
$("m-time").textContent    = META.generatedAt || "—";

// events
$("search").addEventListener("input", e => { state.q = e.target.value.trim().toLowerCase(); renderRows(); });
$("hideGone").addEventListener("change", e => { state.hideGone = e.target.checked; renderRows(); });
document.querySelectorAll("th[data-key]").forEach(th => {
  th.onclick = () => {
    const k = th.dataset.key;
    if(state.key === k) state.dir *= -1; else { state.key = k; state.dir = 1; }
    updateArrows(); renderRows();
  };
});

renderHealth();
renderChips();
updateArrows();
renderRows();
</script>
</body>
</html>
HTML_BODY
} > "$OUT"

c_info "Wrote ${OUT} — ${COUNT} resource(s) in ${REGION}."
command -v open >/dev/null 2>&1 && open "$OUT" || echo "Open it in a browser: ${OUT}"
