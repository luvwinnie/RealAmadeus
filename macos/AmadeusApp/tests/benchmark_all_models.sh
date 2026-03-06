#!/bin/bash
# Full 500-prompt benchmark across all sub-9B models
# Tests emotion tag accuracy, response quality, speed

ENDPOINT="https://llm.nishizaki-leow-lab-alps.org"
PROMPTS_FILE="/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/kurisu_500_prompts.json"
RESULTS_DIR="/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/results"
mkdir -p "$RESULTS_DIR"

SYSTEM_PROMPT="あなたは牧瀬紅莉栖です。Steins;Gateの天才脳科学者で、ツンデレな性格。一人称は「私」。回答は1〜3文で、必ず最初に感情タグ[NORMAL],[SMILE],[ANGRY],[SAD],[SURPRISED],[BLUSH]のいずれか一つを付けてください。"

MODELS=("gemma3:270m" "gemma3:1b" "gemma3:4b" "qwen2.5vl:latest" "qwen3-vl:8b")

# Get total prompt count
TOTAL=$(python3 -c "import json; print(len(json.load(open('$PROMPTS_FILE'))))")
echo "Total prompts: $TOTAL"
echo "Models to test: ${MODELS[*]}"
echo ""

for MODEL in "${MODELS[@]}"; do
    SAFE_NAME=$(echo "$MODEL" | tr ':/' '_')
    OUT_FILE="$RESULTS_DIR/${SAFE_NAME}.jsonl"
    > "$OUT_FILE"

    echo "=========================================="
    echo "MODEL: $MODEL"
    echo "=========================================="

    TOTAL_TIME=0
    SUCCESS=0
    FAIL=0
    EMOTION_OK=0
    EMOTION_FAIL=0
    EMPTY=0
    CHAR_COUNT=0

    for IDX in $(seq 1 $TOTAL); do
        # Extract prompt and category
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

        # Build request JSON
        REQUEST_JSON=$(python3 -c "
import json, sys
req = {
    'model': sys.argv[3],
    'messages': [
        {'role': 'system', 'content': sys.argv[2]},
        {'role': 'user', 'content': sys.argv[1]}
    ],
    'max_tokens': 256,
    'temperature': 0.8,
    'stream': False
}
print(json.dumps(req, ensure_ascii=False))
" "$PROMPT" "$SYSTEM_PROMPT" "$MODEL")

        START=$(python3 -c "import time; print(time.time())")

        RESPONSE=$(curl -s --max-time 60 \
            -H "Content-Type: application/json" \
            -d "$REQUEST_JSON" \
            "$ENDPOINT/v1/chat/completions" 2>&1)

        END=$(python3 -c "import time; print(time.time())")
        ELAPSED=$(python3 -c "print(f'{$END - $START:.2f}')")
        TOTAL_TIME=$(python3 -c "print(f'{$TOTAL_TIME + $ELAPSED:.2f}')")

        # Extract and analyze content
        RESULT=$(python3 -c "
import json, re, sys
try:
    data = json.loads(sys.argv[1])
    content = data['choices'][0]['message']['content'].strip()
    if not content:
        print('EMPTY|||0|||NONE')
    else:
        m = re.match(r'\[(NORMAL|SMILE|ANGRY|SAD|SURPRISED|BLUSH|WINK|DISGUST|SMUG|THINKING|PANIC)\]', content)
        tag = m.group(1) if m else 'MISSING'
        # Strip thinking blocks
        clean = re.sub(r'<think>.*?</think>', '', content, flags=re.DOTALL).strip()
        char_count = len(clean)
        # Escape for shell
        safe_content = clean.replace('\n', ' ')[:200]
        print(f'{safe_content}|||{char_count}|||{tag}')
except Exception as e:
    print(f'ERROR|||0|||NONE')
" "$RESPONSE")

        CONTENT_PREVIEW=$(echo "$RESULT" | python3 -c "import sys; print(sys.stdin.read().split('|||')[0])")
        CHAR_LEN=$(echo "$RESULT" | python3 -c "import sys; print(sys.stdin.read().split('|||')[1])")
        EMOTION_TAG=$(echo "$RESULT" | python3 -c "import sys; print(sys.stdin.read().split('|||')[2].strip())")

        if [ "$EMOTION_TAG" = "NONE" ]; then
            FAIL=$((FAIL + 1))
        elif [ "$CHAR_LEN" = "0" ]; then
            EMPTY=$((EMPTY + 1))
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

        # Save to JSONL
        python3 -c "
import json, sys
result = {
    'id': int(sys.argv[1]),
    'category': sys.argv[2],
    'prompt': sys.argv[3],
    'emotion_tag': sys.argv[4],
    'time_s': float(sys.argv[5]),
    'char_count': int(sys.argv[6]),
    'response_preview': sys.argv[7][:200]
}
print(json.dumps(result, ensure_ascii=False))
" "$IDX" "$CATEGORY" "$PROMPT" "$EMOTION_TAG" "$ELAPSED" "$CHAR_LEN" "$CONTENT_PREVIEW" >> "$OUT_FILE"

        # Progress every 50
        if [ $((IDX % 50)) -eq 0 ]; then
            echo "  [$MODEL] $IDX/$TOTAL done (${ELAPSED}s last)"
        fi
    done

    # Model summary
    AVG_TIME=$(python3 -c "print(f'{$TOTAL_TIME / $TOTAL:.2f}')" 2>/dev/null || echo "0")
    EMOTION_RATE=$(python3 -c "
ok=$EMOTION_OK; fail=$EMOTION_FAIL
total = ok + fail
print(f'{ok/total*100:.1f}%' if total > 0 else 'N/A')
")
    AVG_CHARS=$(python3 -c "print(f'{$CHAR_COUNT / max($SUCCESS,1):.0f}')")

    echo ""
    echo "--- $MODEL RESULTS ---"
    echo "Success: $SUCCESS/$TOTAL | Fail: $FAIL | Empty: $EMPTY"
    echo "Emotion OK: $EMOTION_OK | Missing: $EMOTION_FAIL | Rate: $EMOTION_RATE"
    echo "Avg time: ${AVG_TIME}s | Total: ${TOTAL_TIME}s"
    echo "Avg chars: $AVG_CHARS"
    echo ""

    # Save summary
    python3 -c "
import json
summary = {
    'model': '$MODEL',
    'total': $TOTAL,
    'success': $SUCCESS,
    'fail': $FAIL,
    'empty': $EMPTY,
    'emotion_ok': $EMOTION_OK,
    'emotion_missing': $EMOTION_FAIL,
    'emotion_rate': '$EMOTION_RATE',
    'avg_time_s': $AVG_TIME,
    'total_time_s': $TOTAL_TIME,
    'avg_chars': $AVG_CHARS
}
print(json.dumps(summary, ensure_ascii=False))
" >> "$RESULTS_DIR/summary.jsonl"
done

echo ""
echo "============================================"
echo "FINAL COMPARISON"
echo "============================================"
python3 -c "
import json
results = []
with open('$RESULTS_DIR/summary.jsonl') as f:
    for line in f:
        if line.strip():
            results.append(json.loads(line))

print(f'{\"Model\":30s} {\"Success\":>8s} {\"EmotionOK\":>10s} {\"Rate\":>8s} {\"AvgTime\":>8s} {\"AvgChars\":>9s}')
print('-' * 80)
for r in results:
    print(f'{r[\"model\"]:30s} {r[\"success\"]:>5d}/500 {r[\"emotion_ok\"]:>7d}/500 {r[\"emotion_rate\"]:>8s} {r[\"avg_time_s\"]:>7.2f}s {r[\"avg_chars\"]:>8s}')
"
echo ""
echo "All results saved to: $RESULTS_DIR/"
