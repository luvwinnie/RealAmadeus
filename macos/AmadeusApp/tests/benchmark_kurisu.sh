#!/bin/bash
# Benchmark Kurisu prompts against gemma3:4b
# Runs a representative sample (30 prompts) from the 500-prompt dataset

ENDPOINT="https://llm.nishizaki-leow-lab-alps.org"
MODEL="gemma3:4b"
RESULTS_FILE="/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/benchmark_results.jsonl"
SUMMARY_FILE="/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/benchmark_summary.txt"

SYSTEM_PROMPT="あなたは牧瀬紅莉栖です。Steins;Gateの天才脳科学者で、ツンデレな性格。一人称は「私」。回答は1〜3文で、必ず最初に感情タグ[NORMAL],[SMILE],[ANGRY],[SAD],[SURPRISED],[BLUSH]のいずれか一つを付けてください。"

# Sample 30 prompts: indices covering all major categories
SAMPLE_INDICES=(1 11 21 35 51 65 71 86 101 121 141 151 166 181 191 206 231 246 266 281 301 341 371 401 431 461 481 491 451 500)

> "$RESULTS_FILE"
echo "=== Kurisu Benchmark: $MODEL ===" > "$SUMMARY_FILE"
echo "Date: $(date)" >> "$SUMMARY_FILE"
echo "Endpoint: $ENDPOINT" >> "$SUMMARY_FILE"
echo "Sample size: ${#SAMPLE_INDICES[@]}" >> "$SUMMARY_FILE"
echo "---" >> "$SUMMARY_FILE"

TOTAL_TIME=0
SUCCESS=0
FAIL=0
EMOTION_OK=0
EMOTION_FAIL=0

for IDX in "${SAMPLE_INDICES[@]}"; do
    # Extract prompt using python
    PROMPT=$(python3 -c "
import json, sys
with open('/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/kurisu_500_prompts.json') as f:
    data = json.load(f)
for item in data:
    if item['id'] == int(sys.argv[1]):
        print(item['prompt'])
        break
" "$IDX")

    CATEGORY=$(python3 -c "
import json, sys
with open('/Users/cheesiang_leow/research/amadeus_project/macos/AmadeusApp/tests/kurisu_500_prompts.json') as f:
    data = json.load(f)
for item in data:
    if item['id'] == int(sys.argv[1]):
        print(item['category'])
        break
" "$IDX")

    # Build request JSON
    REQUEST_JSON=$(python3 -c "
import json, sys
prompt = sys.argv[1]
system = sys.argv[2]
model = sys.argv[3]
req = {
    'model': model,
    'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': prompt}
    ],
    'max_tokens': 256,
    'temperature': 0.8,
    'stream': False
}
print(json.dumps(req, ensure_ascii=False))
" "$PROMPT" "$SYSTEM_PROMPT" "$MODEL")

    START=$(python3 -c "import time; print(time.time())")

    RESPONSE=$(curl -s --max-time 30 \
        -H "Content-Type: application/json" \
        -d "$REQUEST_JSON" \
        "$ENDPOINT/v1/chat/completions" 2>&1)

    END=$(python3 -c "import time; print(time.time())")
    ELAPSED=$(python3 -c "print(f'{float(sys.argv[2]) - float(sys.argv[1]):.2f}' )" -c "import sys; print(f'{float(\"$END\") - float(\"$START\"):.2f}')" 2>/dev/null || echo "0")
    ELAPSED=$(python3 -c "print(f'{$END - $START:.2f}')")

    TOTAL_TIME=$(python3 -c "print(f'{$TOTAL_TIME + $ELAPSED:.2f}')")

    # Extract content
    CONTENT=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    content = data['choices'][0]['message']['content']
    print(content)
except:
    print('ERROR')
" "$RESPONSE")

    if [ "$CONTENT" = "ERROR" ] || [ -z "$CONTENT" ]; then
        FAIL=$((FAIL + 1))
        STATUS="FAIL"
        EMOTION_TAG="NONE"
    else
        SUCCESS=$((SUCCESS + 1))
        STATUS="OK"
        # Check emotion tag
        EMOTION_TAG=$(python3 -c "
import re, sys
text = sys.argv[1]
m = re.match(r'\[(NORMAL|SMILE|ANGRY|SAD|SURPRISED|BLUSH|WINK|DISGUST|SMUG|THINKING|PANIC)\]', text)
if m:
    print(m.group(1))
else:
    print('MISSING')
" "$CONTENT")
        if [ "$EMOTION_TAG" = "MISSING" ]; then
            EMOTION_FAIL=$((EMOTION_FAIL + 1))
        else
            EMOTION_OK=$((EMOTION_OK + 1))
        fi
    fi

    # Log result
    printf "[%3d] %-20s | %5ss | %-8s | %s\n" "$IDX" "$CATEGORY" "$ELAPSED" "$EMOTION_TAG" "$PROMPT"
    printf "[%3d] %-20s | %5ss | %-8s | %s\n" "$IDX" "$CATEGORY" "$ELAPSED" "$EMOTION_TAG" "$PROMPT" >> "$SUMMARY_FILE"

    # Truncate content for display
    SHORT_CONTENT=$(echo "$CONTENT" | head -c 120)
    echo "     -> $SHORT_CONTENT"
    echo "     -> $SHORT_CONTENT" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"

    # Save to JSONL
    python3 -c "
import json, sys
result = {
    'id': int(sys.argv[1]),
    'category': sys.argv[2],
    'prompt': sys.argv[3],
    'response': sys.argv[4],
    'emotion_tag': sys.argv[5],
    'time_s': float(sys.argv[6]),
    'status': sys.argv[7]
}
print(json.dumps(result, ensure_ascii=False))
" "$IDX" "$CATEGORY" "$PROMPT" "$CONTENT" "$EMOTION_TAG" "$ELAPSED" "$STATUS" >> "$RESULTS_FILE"
done

echo "" >> "$SUMMARY_FILE"
echo "=== SUMMARY ===" >> "$SUMMARY_FILE"
echo "Total: ${#SAMPLE_INDICES[@]}, Success: $SUCCESS, Fail: $FAIL" >> "$SUMMARY_FILE"
echo "Emotion tags correct: $EMOTION_OK, Missing: $EMOTION_FAIL" >> "$SUMMARY_FILE"
AVG_TIME=$(python3 -c "print(f'{$TOTAL_TIME / ${#SAMPLE_INDICES[@]}:.2f}')")
echo "Average time: ${AVG_TIME}s, Total time: ${TOTAL_TIME}s" >> "$SUMMARY_FILE"
EMOTION_RATE=$(python3 -c "
total = $EMOTION_OK + $EMOTION_FAIL
print(f'{$EMOTION_OK/total*100:.1f}%' if total > 0 else 'N/A')
")
echo "Emotion tag accuracy: $EMOTION_RATE" >> "$SUMMARY_FILE"

echo ""
echo "=== SUMMARY ==="
echo "Total: ${#SAMPLE_INDICES[@]}, Success: $SUCCESS, Fail: $FAIL"
echo "Emotion tags correct: $EMOTION_OK, Missing: $EMOTION_FAIL"
echo "Average time: ${AVG_TIME}s, Total time: ${TOTAL_TIME}s"
echo "Emotion tag accuracy: $EMOTION_RATE"
echo ""
echo "Results saved to: $RESULTS_FILE"
echo "Summary saved to: $SUMMARY_FILE"
