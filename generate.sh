#!/bin/bash
set -e

BASE_URL="https://generativelanguage.googleapis.com/v1beta"
API_KEY="${GEMINI_API_KEY}"
OUTPUT_DIR="/home/node/.openclaw/workspace/yakiniku-video"
mkdir -p "$OUTPUT_DIR"

# Scene prompts
PROMPT1="Extreme close-up of glowing red charcoal in a Japanese shichirin grill, oil dripping onto embers causing small flames to flicker, smoke rising beautifully. Then transition to slow-motion of thick-cut marbled wagyu kalbi beef being placed on the wire grill grate, sizzling intensely with juice splashing. Warm amber lighting, shallow depth of field, cinematic macro photography, 24fps film look with warm color grading. No text, no watermark, no subtitles."

PROMPT2="Close-up of perfectly grilled Japanese beef being flipped with metal tongs on a charcoal grill, revealing a beautiful seared crust and juicy pink interior cross-section, steam and smoke rising. Then pull back to show a warm casual izakaya-style yakiniku restaurant interior, friends clinking cold beer glasses and laughing together around a grill table, warm ambient golden lighting, cozy Japanese atmosphere. Cinematic shallow depth of field, 24fps, warm color grading with rich reds and ambers. No text, no watermark, no subtitles."

PROMPT3="A beautifully arranged plate of premium marbled Japanese domestic beef (wagyu) being gently placed on a wooden table in a casual izakaya-style yakiniku restaurant. The meat glistens under warm amber lighting. Background is softly blurred showing cozy restaurant interior with warm golden lights. Elegant food photography style, shallow depth of field, cinematic 24fps, warm color grading. No text, no watermark, no subtitles."

declare -a PROMPTS=("$PROMPT1" "$PROMPT2" "$PROMPT3")
declare -a DURATIONS=(8 8 6)
declare -a NAMES=("scene1_charcoal_meat" "scene2_flip_interior" "scene3_plating")
declare -a OPS=()

# Step 1: Start all generations
for i in 0 1 2; do
  echo "=== Starting generation: ${NAMES[$i]} (${DURATIONS[$i]}s) ==="
  
  response=$(curl -s "${BASE_URL}/models/veo-3.0-generate-001:predictLongRunning" \
    -H "x-goog-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "{
      \"instances\": [{
        \"prompt\": \"${PROMPTS[$i]}\"
      }],
      \"parameters\": {
        \"sampleCount\": 1,
        \"resolution\": \"720p\",
        \"aspectRatio\": \"16:9\",
        \"durationSeconds\": ${DURATIONS[$i]}
      }
    }")
  
  op_name=$(echo "$response" | jq -r '.name // empty')
  
  if [[ -z "$op_name" ]]; then
    echo "ERROR starting ${NAMES[$i]}:"
    echo "$response" | jq .
    OPS+=("ERROR")
  else
    echo "Operation: $op_name"
    OPS+=("$op_name")
  fi
done

echo ""
echo "=== All operations started ==="
echo ""

# Step 2: Poll all operations
for i in 0 1 2; do
  if [[ "${OPS[$i]}" == "ERROR" ]]; then
    echo "Skipping ${NAMES[$i]} (failed to start)"
    continue
  fi
  
  echo "--- Waiting for ${NAMES[$i]} ---"
  while true; do
    status=$(curl -s -H "x-goog-api-key: $API_KEY" "${BASE_URL}/${OPS[$i]}")
    is_done=$(echo "$status" | jq -r '.done // false')
    
    if [[ "$is_done" == "true" ]]; then
      # Check for error
      error=$(echo "$status" | jq -r '.error // empty')
      if [[ -n "$error" && "$error" != "null" ]]; then
        echo "ERROR for ${NAMES[$i]}:"
        echo "$status" | jq .error
        break
      fi
      
      # Extract video URI
      video_uri=$(echo "$status" | jq -r '.response.generateVideoResponse.generatedSamples[0].video.uri // empty')
      if [[ -n "$video_uri" ]]; then
        echo "Downloading ${NAMES[$i]}..."
        curl -s -L -H "x-goog-api-key: $API_KEY" "$video_uri" --output "${OUTPUT_DIR}/${NAMES[$i]}.mp4"
        echo "Saved: ${OUTPUT_DIR}/${NAMES[$i]}.mp4"
      else
        echo "No video URI found for ${NAMES[$i]}"
        echo "$status" | jq . > "${OUTPUT_DIR}/${NAMES[$i]}_response.json"
      fi
      break
    fi
    
    echo "  Still processing ${NAMES[$i]}... (waiting 15s)"
    sleep 15
  done
done

echo ""
echo "=== Done ==="
ls -la "${OUTPUT_DIR}"/*.mp4 2>/dev/null || echo "No videos generated"
