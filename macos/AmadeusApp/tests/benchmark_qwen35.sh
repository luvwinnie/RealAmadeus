#!/bin/bash
# Benchmark qwen3.5 models using Ollama NATIVE API (/api/chat) with think:false
# think:true is NOT viable (61-120s per response)
# Improved emotion tag detection: handles [TAG], 【TAG】, **[TAG]**, bare TAG

ENDPOINT="https://llm.nishizaki-leow-lab-alps.org"
PROMPTS_FILE="/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/kurisu_500_prompts.json"
RESULTS_DIR="/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/results"
mkdir -p "$RESULTS_DIR"

BASE_SYSTEM='あなたは牧瀬紅莉栖です。Steins;Gateの天才脳科学者で、ツンデレな性格。一人称は「私」。回答は1〜3文で、必ず最初に感情タグ[NORMAL],[SMILE],[ANGRY],[SAD],[SURPRISED],[BLUSH]のいずれか一つを付けてください。'

TOTAL=$(python3 -c "import json; print(len(json.load(open('$PROMPTS_FILE'))))")

MODELS=("qwen3.5:0.8b" "qwen3.5:2b" "qwen3.5:4b" "qwen3.5:9b")

> "$RESULTS_DIR/qwen35_summary.jsonl"

# Create the response parser as a reusable script
cat << 'PYEOF' > /tmp/parse_response.py
import json, re, sys

# Case-insensitive tag names
TAG_NAMES = ['NORMAL', 'SMILE', 'ANGRY', 'SAD', 'SURPRISED', 'BLUSH',
             'WINK', 'DISGUST', 'SMUG', 'THINKING', 'PANIC']
TAGS_CI = '(' + '|'.join(TAG_NAMES) + ')'  # case-insensitive group

def normalize_tag(tag_str):
    """Normalize tag to uppercase canonical form"""
    up = tag_str.upper().strip()
    if up in TAG_NAMES:
        return up
    return None

def detect_tag(text):
    """Detect emotion tag in ANY format the model might use"""
    first150 = text[:150]

    # --- AT START patterns ---
    # [TAG]
    m = re.match(r'\s*\[' + TAGS_CI + r'\]', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '[TAG]'
    # 【TAG】
    m = re.match(r'\s*【' + TAGS_CI + r'】', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '【TAG】'
    # **[TAG]** or **TAG**
    m = re.match(r'\s*\*\*\[?' + TAGS_CI + r'\]?\*\*', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '**TAG**'
    # (TAG) half-width parens
    m = re.match(r'\s*\(' + TAGS_CI + r'\)', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '(TAG)'
    # （TAG） full-width parens
    m = re.match(r'\s*（' + TAGS_CI + r'）', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '（TAG）'
    # <TAG>
    m = re.match(r'\s*<' + TAGS_CI + r'>', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '<TAG>'
    # TAG: or TAG\s at very start (bare)
    m = re.match(r'\s*' + TAGS_CI + r'[\s:!！\.]', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), 'bare start'

    # --- ANYWHERE in first 150 chars ---
    # [TAG]
    m = re.search(r'\[' + TAGS_CI + r'\]', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '[TAG] mid'
    # 【TAG】
    m = re.search(r'【' + TAGS_CI + r'】', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '【TAG】mid'
    # (TAG)
    m = re.search(r'\(' + TAGS_CI + r'\)', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '(TAG) mid'
    # （TAG）
    m = re.search(r'（' + TAGS_CI + r'）', first150, re.IGNORECASE)
    if m: return normalize_tag(m.group(1)), '（TAG）mid'
    # Bare word match anywhere
    m = re.search(r'\b' + TAGS_CI + r'\b', first150, re.IGNORECASE)
    if m:
        t = normalize_tag(m.group(1))
        if t: return t, 'bare mid'

    return 'MISSING', 'none'

try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    content = data.get('message', {}).get('content', '').strip()
    if not content:
        print('EMPTY|||0|||NONE|||none')
    else:
        tag, fmt = detect_tag(content)
        if tag is None:
            tag = 'MISSING'
            fmt = 'none'
        safe = content.replace('\n', ' ')[:200]
        print(f'{safe}|||{len(content)}|||{tag}|||{fmt}')
except:
    print('ERROR|||0|||NONE|||none')
PYEOF

for MODEL in "${MODELS[@]}"; do
    SAFE_NAME=$(echo "$MODEL" | tr ':/' '_')
    LABEL="${SAFE_NAME}_nothink"
    OUT_FILE="$RESULTS_DIR/${LABEL}.jsonl"
    > "$OUT_FILE"

    echo "=========================================="
    echo "MODEL: $MODEL (think:false)"
    echo "=========================================="

    TOTAL_TIME=0
    SUCCESS=0
    FAIL=0
    EMOTION_OK=0
    EMOTION_FAIL=0
    CHAR_COUNT=0
    declare -A FMT_COUNTS

    for IDX in $(seq 1 $TOTAL); do
        PROMPT_DATA=$(python3 -c "
import json, sys
with open('$PROMPTS_FILE') as f:
    data = json.load(f)
for item in data:
    if item['id'] == int(sys.argv[1]):
        print(item['prompt'])
        print(item['category'])
        break
" "$IDX")
        PROMPT=$(echo "$PROMPT_DATA" | head -1)
        CATEGORY=$(echo "$PROMPT_DATA" | tail -1)

        TMPJSON=$(mktemp)
        python3 -c "
import json, sys
req = {
    'model': sys.argv[1],
    'messages': [
        {'role': 'system', 'content': sys.argv[2]},
        {'role': 'user', 'content': sys.argv[3]}
    ],
    'think': False,
    'stream': False
}
with open(sys.argv[4], 'w') as f:
    json.dump(req, f, ensure_ascii=False)
" "$MODEL" "$BASE_SYSTEM" "$PROMPT" "$TMPJSON"

        START=$(python3 -c "import time; print(time.time())")

        RESPONSE_FILE=$(mktemp)
        curl -s --max-time 60 \
            -H "Content-Type: application/json" \
            -d @"$TMPJSON" \
            "$ENDPOINT/api/chat" > "$RESPONSE_FILE" 2>&1

        END=$(python3 -c "import time; print(time.time())")
        ELAPSED=$(python3 -c "print(f'{$END - $START:.2f}')")
        TOTAL_TIME=$(python3 -c "print(f'{$TOTAL_TIME + $ELAPSED:.2f}')")

        RESULT=$(python3 /tmp/parse_response.py "$RESPONSE_FILE")
        rm -f "$TMPJSON" "$RESPONSE_FILE"

        CONTENT_PREVIEW=$(echo "$RESULT" | python3 -c "import sys; p=sys.stdin.read().split('|||'); print(p[0])")
        CHAR_LEN=$(echo "$RESULT" | python3 -c "import sys; p=sys.stdin.read().split('|||'); print(p[1])")
        EMOTION_TAG=$(echo "$RESULT" | python3 -c "import sys; p=sys.stdin.read().split('|||'); print(p[2].strip())")
        TAG_FMT=$(echo "$RESULT" | python3 -c "import sys; p=sys.stdin.read().split('|||'); print(p[3].strip())")

        if [ "$EMOTION_TAG" = "NONE" ] || [ "$CHAR_LEN" = "0" ]; then
            FAIL=$((FAIL + 1))
        else
            SUCCESS=$((SUCCESS + 1))
            CHAR_COUNT=$((CHAR_COUNT + CHAR_LEN))
            if [ "$EMOTION_TAG" = "MISSING" ]; then
                EMOTION_FAIL=$((EMOTION_FAIL + 1))
            else
                EMOTION_OK=$((EMOTION_OK + 1))
            fi
        fi

        python3 -c "
import json, sys
result = {
    'id': int(sys.argv[1]),
    'category': sys.argv[2],
    'prompt': sys.argv[3],
    'emotion_tag': sys.argv[4],
    'tag_format': sys.argv[5],
    'time_s': float(sys.argv[6]),
    'char_count': int(sys.argv[7]),
    'response_preview': sys.argv[8][:200]
}
with open(sys.argv[9], 'a') as f:
    f.write(json.dumps(result, ensure_ascii=False) + '\n')
" "$IDX" "$CATEGORY" "$PROMPT" "$EMOTION_TAG" "$TAG_FMT" "$ELAPSED" "$CHAR_LEN" "$CONTENT_PREVIEW" "$OUT_FILE"

        if [ $((IDX % 50)) -eq 0 ]; then
            echo "  [$MODEL] $IDX/$TOTAL (${ELAPSED}s) ok=$SUCCESS fail=$FAIL emo=$EMOTION_OK"
        fi
    done

    AVG_TIME=$(python3 -c "print(f'{$TOTAL_TIME / $TOTAL:.2f}')")
    EMOTION_RATE=$(python3 -c "
ok=$EMOTION_OK; fail=$EMOTION_FAIL; total=ok+fail
print(f'{ok/total*100:.1f}%' if total>0 else 'N/A')
")
    AVG_CHARS=$(python3 -c "print(f'{$CHAR_COUNT / max($SUCCESS,1):.0f}')")

    # Count tag formats from jsonl
    TAG_FMT_SUMMARY=$(python3 -c "
import json, collections
counts = collections.Counter()
with open('$OUT_FILE') as f:
    for line in f:
        if line.strip():
            d = json.loads(line)
            counts[d.get('tag_format','none')] += 1
for fmt, c in counts.most_common():
    print(f'    {fmt}: {c}')
")

    echo ""
    echo "--- $MODEL (think:false) RESULTS ---"
    echo "Success: $SUCCESS/$TOTAL | Fail: $FAIL"
    echo "Emotion OK: $EMOTION_OK | Missing: $EMOTION_FAIL | Rate: $EMOTION_RATE"
    echo "Avg time: ${AVG_TIME}s | Total: ${TOTAL_TIME}s"
    echo "Avg chars: $AVG_CHARS"
    echo "Tag formats:"
    echo "$TAG_FMT_SUMMARY"
    echo ""

    python3 -c "
import json
s = {
    'model': '$MODEL',
    'label': '$LABEL',
    'think': False,
    'total': $TOTAL,
    'success': $SUCCESS,
    'fail': $FAIL,
    'emotion_ok': $EMOTION_OK,
    'emotion_missing': $EMOTION_FAIL,
    'emotion_rate': '$EMOTION_RATE',
    'avg_time_s': $AVG_TIME,
    'total_time_s': $TOTAL_TIME,
    'avg_chars': int('$AVG_CHARS')
}
print(json.dumps(s, ensure_ascii=False))
" >> "$RESULTS_DIR/qwen35_summary.jsonl"
done

echo ""
echo "============================================"
echo "QWEN3.5 (think:false) vs GEMMA3:4B"
echo "============================================"
python3 -c "
import json
results = []
with open('$RESULTS_DIR/qwen35_summary.jsonl') as f:
    for line in f:
        if line.strip(): results.append(json.loads(line))

print(f'{\"Model\":25s} {\"Success\":>10s} {\"Emotion\":>10s} {\"Rate\":>8s} {\"Time\":>7s} {\"Chars\":>6s}')
print('-' * 72)
for r in results:
    print(f'{r[\"model\"]:25s} {r[\"success\"]:>5d}/500  {r[\"emotion_ok\"]:>5d}/500  {r[\"emotion_rate\"]:>8s} {r[\"avg_time_s\"]:>6.2f}s {r[\"avg_chars\"]:>5d}')
print('-' * 72)
print(f'{\"gemma3:4b (reference)\":25s}   497/500    497/500    100.0%   1.51s   124')
print()
print('Note: qwen3.5 think:true is NOT viable (61-120s per response)')
"
