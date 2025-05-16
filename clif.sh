#!/usr/bin/env bash
# Natural language shell helper - CLI Friend, a.k.a. Clif
#
# Usage:
#   export OPENAI_API_KEY=sk-...
#   ./clif.sh
#
# Needs: curl and jq (sudo apt install jq)

set -euo pipefail

MODEL=${OPENAI_MODEL:-"gpt-4o-mini"}

# Words that end the program
declare -r QUIT_REGEX='^(exit|quit|q)$'

# Check for OpenAI API key
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  read -rp "Please enter your OpenAI API key: " OPENAI_API_KEY
  export OPENAI_API_KEY
  # Store the key in the user's shell profile for future use
  SHELL_NAME=$(basename "$SHELL")
  if [[ "$SHELL_NAME" == "zsh" ]]; then
    PROFILE_FILE="$HOME/.zshrc"
  else
    PROFILE_FILE="$HOME/.bash_profile"
  fi
  if ! grep -q "^export OPENAI_API_KEY=" "$PROFILE_FILE" 2>/dev/null; then
    echo "export OPENAI_API_KEY=\"$OPENAI_API_KEY\"" >> "$PROFILE_FILE"
    echo "OPENAI_API_KEY saved to $PROFILE_FILE. It will be available in new terminal sessions."
  fi
fi

prompt_user() {
  # If arguments are provided, use them as the request
  if [[ $# -gt 0 ]]; then
    USER_REQUEST="$*"
  else
    # Ask for the next idea from the user (natural language)
    read -rp "💭  " USER_REQUEST
  fi
}

ask_confirmation() {
  # Ask if the command should be executed
  read -rp "❓ ($TOKENS_USED tokens) Run? [Y/n] " CONFIRM
  # If user just hits return, consider it as "yes"
  if [[ -z "$CONFIRM" ]]; then
    CONFIRM="y"
  fi
}

# Track if the script was started with arguments
STARTED_WITH_ARGS=0
if [[ $# -gt 0 ]]; then
  STARTED_WITH_ARGS=1
fi

while true; do
  if [[ $# -gt 0 ]]; then
    prompt_user "$@"
    # After first run with arguments, clear them so we don't loop with the same request
    set --
  else
    prompt_user
  fi
  if [[ $USER_REQUEST =~ $QUIT_REGEX ]]; then
    echo "bye"
    exit 0
  fi

  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "OPENAI_API_KEY env variable is missing."
    exit 1
  fi

  # Ask the model for a plain bash command
  RESPONSE=$(curl -sS https://api.openai.com/v1/chat/completions \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "'"${MODEL}"'",
      "messages": [
        {"role": "system", "content": "You are a Mac OS X shell expert. Return one bash command only. No code fences, no comments."},
        {"role": "user", "content": "'"$(echo "$USER_REQUEST" | sed 's/"/\\"/g')"'"}
      ],
      "temperature": 0
    }')

  COMMAND=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' | sed -e 's/^\s*//' -e 's/\s*$//')
  TOKENS_USED=$(echo "$RESPONSE" | jq -r '.usage.total_tokens')

  echo "⚡ $COMMAND"

  ask_confirmation
  if [[ $CONFIRM =~ ^[Yy]$ ]]; then
    # Run the command in the current shell
    eval "$COMMAND"
  fi
  # If started with arguments, exit after first run
  if [[ $STARTED_WITH_ARGS -eq 1 ]]; then
    exit 0
  fi
  echo
done
