RUNS_TMP_FILE="runs.json"
DISPATCHED_RUN_TMP_FILE="dispatched_run.json"
RUN_NAME="$INPUT_RUN_NAME - $(date)"
echo -e "\x1b[35;49mDispatching \x1b[36;49m$INPUT_WORKFLOW_LOCATOR\x1b[35;49m with run name \x1b[36;49m$RUN_NAME"

GIVEN_INPUTS="$INPUT_WORKFLOW_INPUTS"
MANDATORY_INPUTS=""
COMBINED_INPUTS=$(echo "$GIVEN_INPUTS" "$MANDATORY_INPUTS" | jq --raw-output --slurp '.[0] * .[1]')
echo "::group::Dispatched run inputs"
echo "$COMBINED_INPUTS" | jq --color-output '.'
echo "::endgroup::"

curl "https://api.github.com/repos/$INPUT_WORKFLOW_LOCATOR/dispatches" \
  --fail-with-body \
  --no-progress-meter \
  -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -d '{
    "ref": "main",
    "inputs": '"$COMBINED_INPUTS"'
  }' \
|& sed "s/^/\x1b[91;49m/" # Change curl output color to bright red

# Fail if curl failed, read piped return code
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  exit 2
fi

for ((i = 1; i <=50; i++)); do        
  echo -e "\x1b[35;49mWaiting for dispatched run, attempt \x1b[36;49m$i\x1b[35;49m/\x1b[36;49m50"

  curl "https://api.github.com/repos/$INPUT_WORKFLOW_LOCATOR/runs" \
    --fail-with-body \
    --no-progress-meter \
    -H "Authorization: token $GITHUB_TOKEN" \
    -o "$RUNS_TMP_FILE" \
  |& sed "s/^/\x1b[91;49m/" # Change curl output color to bright red
  
  # Fail if curl failed, read piped return code
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    exit 3
  fi

  # JQ will save empty file if run was not found
  jq '.workflow_runs[] | select(.name == "'"$RUN_NAME"'")' "$RUNS_TMP_FILE" > "$DISPATCHED_RUN_TMP_FILE"

  if grep -q "id" "$DISPATCHED_RUN_TMP_FILE"; then
    HTML_URL=$(jq --raw-output '.html_url' "$DISPATCHED_RUN_TMP_FILE")
    STATUS=$(jq --raw-output '.status' "$DISPATCHED_RUN_TMP_FILE")
    echo -e "\x1b[35;49mDispatched run logs url: \x1b[36;49m$HTML_URL\x1b[35;49m, status: \x1b[36;49m$STATUS"
    echo "::group::Dispatched run details"
    jq --color-output '.' "$DISPATCHED_RUN_TMP_FILE"
    echo "::endgroup::"

    if jq --exit-status '.status == "completed"' $DISPATCHED_RUN_TMP_FILE > /dev/null 2>&1; then
      CONCLUSION=$(jq --raw-output '.conclusion' "$DISPATCHED_RUN_TMP_FILE")
      echo -e "\x1b[35;49mDispatched run finished, final conclusion: \x1b[36;49m$CONCLUSION"
      if [ "$CONCLUSION" == "success" ]; then
        exit 0
      else
        exit 1
      fi
    fi
  fi

  if [ $i -eq 50 ]; then
    echo -e "\x1b[91;49mDispatched run not found"
    exit 4
  fi

  sleep 10
done
