#!/bin/bash
# Benchmark thinking vs non-thinking for models that support it
# Tests: qwen3-vl:8b (think/no_think), nemotron-nano-9b (think/no_think)

ENDPOINT="https://llm.nishizaki-leow-lab-alps.org"
PROMPTS_FILE="/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/kurisu_500_prompts.json"
RESULTS_DIR="/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/results"
mkdir -p "$RESULTS_DIR"

BASE_SYSTEM="あなたは牧瀬紅莉栖です。Steins;Gateの天才脳科学者で、ツンデレな性格。一人称は「私」。回答は1〜3文で、必ず最初に感情タグ[NORMAL],[SMILE],[ANGRY],[SAD],[SURPRISED],[BLUSH]のいずれか一つを付けてください。"

TOTAL=$(python3 -c "import json; print(len(json.load(open('$PROMPTS_FILE'))))")

# Test configs: model|label|system_suffix|think_param
CONFIGS=(
    "qwen3-vl:8b|qwen3vl_think|（深く考えてから回答してください）|"
    "qwen3-vl:8b|qwen3vl_nothink|/no_think|"
    "nemotron-nano-9b-v2-japanese:latest|nemotron_think|（深く考えてから回答してください）|"
    "nemotron-nano-9b-v2-japanese:latest|nemotron_nothink|思考プロセスを出力せず、回答のみ出力してください。|"
)

> "$RESULTS_DIR/thinking_summary.jsonl"

for CONFIG in "${CONFIGS[@]}"; do
    IFS='|' read -r MODEL LABEL SUFFIX THINK_PARAM <<< "$CONFIG"
    OUT_FILE="$RESULTS_DIR/${LABEL}.jsonl"
    > "$OUT_FILE"

    SYSTEM_PROMPT="${BASE_SYSTEM} ${SUFFIX}"

    echo "=========================================="
    echo "MODEL: $MODEL ($LABEL)"
    echo "System suffix: $SUFFIX"
    echo "=========================================="

    TOTAL_TIME=0
    SUCCESS=0
    FAIL=0
    EMOTION_OK=0
    EMOTION_FAIL=0
    EMPTY=0
    CHAR_COUNT=0
    THINK_TOKENS=0

    for IDX in $(seq 1 $TOTAL); do
        PROMPT=$(python3 -c "
import json, sys
with open('$PROMPTS_FILE') as f:
    data = json.load(f)
for item in data:
    if item['id'] == int(sys.argv[1]):
        print(item['prompt'])
        break
" "$IDX")

        CATEGORY=$(python3 -c "
import json, sys
with open('$PROMPTS_FILE') as f:
    data = json.load(f)
for item in data:
    if item['id'] == int(sys.argv[1]):
        print(item['category'])
        break
" "$IDX")

        REQUEST_JSON=$(python3 -c "
import json, sys
req = {
    'model': sys.argv[3],
    'messages': [
        {'role': 'system', 'content': sys.argv[2]},
        {'role': 'user', 'content': sys.argv[1]}
    ],
    'max_tokens': 512,
    'temperature': 0.8,
    'stream': False
}
print(json.dumps(req, ensure_ascii=False))
" "$PROMPT" "$SYSTEM_PROMPT" "$MODEL")

        START=$(python3 -c "import time; print(time.time())")

        RESPONSE=$(curl -s --max-time 120 \
            -H "Content-Type: application/json" \
            -d "$REQUEST_JSON" \
            "$ENDPOINT/v1/chat/completions" 2>&1)

        END=$(python3 -c "import time; print(time.time())")
        ELAPSED=$(python3 -c "print(f'{$END - $START:.2f}')")
        TOTAL_TIME=$(python3 -c "print(f'{$TOTAL_TIME + $ELAPSED:.2f}')")

        RESULT=$(python3 -c "
import json, re, sys
try:
    data = json.loads(sys.argv[1])
    content = data['choices'][0]['message']['content'].strip()
    if not content:
        print('EMPTY|||0|||NONE|||0')
    else:
        # Count thinking tokens
        think_matches = re.findall(r'<think>(.*?)</think>', content, re.DOTALL)
        think_chars = sum(len(m) for m in think_matches)
        # Strip thinking blocks
        clean = re.sub(r'<think>.*?</think>', '', content, flags=re.DOTALL).strip()
        if not clean:
            print(f'EMPTY|||0|||NONE|||{think_chars}')
        else:
            m = re.match(r'\[(NORMAL|SMILE|ANGRY|SAD|SURPRISED|BLUSH|WINK|DISGUST|SMUG|THINKING|PANIC)\]', clean)
            tag = m.group(1) if m else 'MISSING'
            char_count = len(clean)
            safe = clean.replace('\n', ' ')[:200]
            print(f'{safe}|||{char_count}|||{tag}|||{think_chars}')
except Exception as e:
    print(f'ERROR|||0|||NONE|||0')
" "$RESPONSE")

        CONTENT_PREVIEW=$(echo "$RESULT" | python3 -c "import sys; parts=sys.stdin.read().split('|||'); print(parts[0])")
        CHAR_LEN=$(echo "$RESULT" | python3 -c "import sys; parts=sys.stdin.read().split('|||'); print(parts[1])")
        EMOTION_TAG=$(echo "$RESULT" | python3 -c "import sys; parts=sys.stdin.read().split('|||'); print(parts[2].strip())")
        THINK_LEN=$(echo "$RESULT" | python3 -c "import sys; parts=sys.stdin.read().split('|||'); print(parts[3].strip())")

        if [ "$EMOTION_TAG" = "NONE" ] || [ "$CHAR_LEN" = "0" ]; then
            FAIL=$((FAIL + 1))
        else
            SUCCESS=$((SUCCESS + 1))
            CHAR_COUNT=$((CHAR_COUNT + CHAR_LEN))
            THINK_TOKENS=$((THINK_TOKENS + THINK_LEN))
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
    'time_s': float(sys.argv[5]),
    'char_count': int(sys.argv[6]),
    'think_chars': int(sys.argv[7]),
    'response_preview': sys.argv[8][:200]
}
print(json.dumps(result, ensure_ascii=False))
" "$IDX" "$CATEGORY" "$PROMPT" "$EMOTION_TAG" "$ELAPSED" "$CHAR_LEN" "$THINK_LEN" "$CONTENT_PREVIEW" >> "$OUT_FILE"

        if [ $((IDX % 50)) -eq 0 ]; then
            echo "  [$LABEL] $IDX/$TOTAL done (${ELAPSED}s last)"
        fi
    done

    AVG_TIME=$(python3 -c "print(f'{$TOTAL_TIME / $TOTAL:.2f}')" 2>/dev/null || echo "0")
    EMOTION_RATE=$(python3 -c "
ok=$EMOTION_OK; fail=$EMOTION_FAIL
total = ok + fail
print(f'{ok/total*100:.1f}%' if total > 0 else 'N/A')
")
    AVG_CHARS=$(python3 -c "print(f'{$CHAR_COUNT / max($SUCCESS,1):.0f}')")
    AVG_THINK=$(python3 -c "print(f'{$THINK_TOKENS / max($SUCCESS,1):.0f}')")

    echo ""
    echo "--- $LABEL RESULTS ---"
    echo "Success: $SUCCESS/$TOTAL | Fail: $FAIL"
    echo "Emotion OK: $EMOTION_OK | Missing: $EMOTION_FAIL | Rate: $EMOTION_RATE"
    echo "Avg time: ${AVG_TIME}s | Total: ${TOTAL_TIME}s"
    echo "Avg response chars: $AVG_CHARS | Avg think chars: $AVG_THINK"
    echo ""

    python3 -c "
import json
summary = {
    'model': '$MODEL',
    'label': '$LABEL',
    'total': $TOTAL,
    'success': $SUCCESS,
    'fail': $FAIL,
    'emotion_ok': $EMOTION_OK,
    'emotion_missing': $EMOTION_FAIL,
    'emotion_rate': '$EMOTION_RATE',
    'avg_time_s': $AVG_TIME,
    'total_time_s': $TOTAL_TIME,
    'avg_chars': int('$AVG_CHARS'),
    'avg_think_chars': int('$AVG_THINK')
}
print(json.dumps(summary, ensure_ascii=False))
" >> "$RESULTS_DIR/thinking_summary.jsonl"
done

echo ""
echo "============================================"
echo "THINKING vs NO-THINKING COMPARISON"
echo "============================================"
python3 -c "
import json
results = []
with open('$RESULTS_DIR/thinking_summary.jsonl') as f:
    for line in f:
        if line.strip():
            results.append(json.loads(line))

print(f'{\"Label\":30s} {\"Success\":>10s} {\"EmotionOK\":>10s} {\"Rate\":>8s} {\"AvgTime\":>8s} {\"Chars\":>6s} {\"Think\":>7s}')
print('-' * 85)
for r in results:
    print(f'{r[\"label\"]:30s} {r[\"success\"]:>5d}/500  {r[\"emotion_ok\"]:>5d}/500  {r[\"emotion_rate\"]:>8s} {r[\"avg_time_s\"]:>7.2f}s {r[\"avg_chars\"]:>5d} {r[\"avg_think_chars\"]:>6d}')
"
