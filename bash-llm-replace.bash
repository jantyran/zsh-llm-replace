#!/usr/bin/env bash

# Bash/readline variant of zsh-llm-replace.
# Source this file from ~/.bashrc, then press Ctrl+O on a natural-language line.

[[ $- == *i* ]] || return 0

if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  return 0
fi

__bash_llm_os_description() {
  local os="${ZSH_AI_COMMANDS_OS:-auto}"

  if [[ "$os" == auto ]]; then
    case "$(uname -s 2>/dev/null)" in
      Darwin) os=macos ;;
      Linux) os=linux ;;
      *) os="$(uname -s 2>/dev/null || printf unknown)" ;;
    esac
  fi

  case "${os,,}" in
    macos|darwin)
      printf '%s\n' "bash on macOS (Darwin). Prefer BSD/macOS-compatible commands unless GNU tools are explicitly requested."
      ;;
    linux|ubuntu)
      printf '%s\n' "bash on Linux (Ubuntu/Debian-like). Prefer GNU coreutils and Linux tools."
      ;;
    *)
      printf 'bash on %s.\n' "$os"
      ;;
  esac
}

__bash_llm_available_commands() {
  local candidates available cmd joined
  candidates=(rg jq fzf fd sed awk perl curl git find xargs du sort grep ss lsof ps kill pkill systemctl journalctl apt apt-get)
  available=()

  for cmd in "${candidates[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      available+=("$cmd")
    fi
  done

  joined=""
  for cmd in "${available[@]}"; do
    [[ -n "$joined" ]] && joined+=", "
    joined+="$cmd"
  done
  printf '%s\n' "$joined"
}

__bash_llm_system_prompt() {
  local os_description available_commands extra_environment
  os_description="$(__bash_llm_os_description)"
  available_commands="$(__bash_llm_available_commands)"
  extra_environment="${ZSH_AI_COMMANDS_ENVIRONMENT:-}"

  cat <<PROMPT
You are an expert sysadmin and shell scripter. Given a task description, output a single shell one-liner.

Environment:
- Shell: ${os_description}
- Available beyond the shell defaults: ${available_commands:-unknown}.
${extra_environment:+- Additional user-provided environment notes: ${extra_environment}
}
Output rules:
- Print ONLY the bare command. Nothing else.
- No markdown, no code fences, no backticks, no commentary, no leading/trailing whitespace.
- The command must be a single logical line. Use pipes, &&, ||, ;, or subshells to chain steps. Never use literal newlines.
- Quoting: prefer single quotes for fixed strings, double quotes when variable expansion or escapes are needed. Escape carefully inside nested quotes.
- Prefer sensible defaults, but when you can't, use <placeholder> for values that must be filled in, e.g. <file>, <pattern>, <port>.
- If you must include commentary, wrap the command in a \`\`\` block so it can be extracted.

Command quality:
- Prefer simple, robust solutions. Avoid unnecessary subshells or processes.
- Prefer commands that are native to the detected OS and installed tools.
- When the task is ambiguous, pick the most common interpretation rather than asking for clarification.
PROMPT
}

__bash_llm_resolve_config() {
  if [[ "${ZSH_AI_COMMANDS_MODEL:-}" == or:* ]]; then
    ZSH_AI_COMMANDS_PROVIDER=openrouter
    ZSH_AI_COMMANDS_MODEL="${ZSH_AI_COMMANDS_MODEL#or:}"
  fi

  if [[ -z "${ZSH_AI_COMMANDS_PROVIDER:-}" ]]; then
    if [[ -n "${ZSH_AI_COMMANDS_GEMINI_API_KEY:-}" ]]; then
      ZSH_AI_COMMANDS_PROVIDER=gemini
    elif [[ -n "${ZSH_AI_COMMANDS_OPENAI_API_KEY:-}" ]]; then
      ZSH_AI_COMMANDS_PROVIDER=openai
    elif [[ -n "${ZSH_AI_COMMANDS_OPENROUTER_API_KEY:-}" ]]; then
      ZSH_AI_COMMANDS_PROVIDER=openrouter
    else
      printf '%s\n' "bash-llm-replace: no API key set" >&2
      return 1
    fi
  fi

  case "$ZSH_AI_COMMANDS_PROVIDER" in
    gemini)
      [[ -n "${ZSH_AI_COMMANDS_GEMINI_API_KEY:-}" ]] || { printf '%s\n' "bash-llm-replace: provider=gemini but ZSH_AI_COMMANDS_GEMINI_API_KEY not set" >&2; return 1; }
      : "${ZSH_AI_COMMANDS_MODEL:=gemini-3-flash-preview}"
      ;;
    openai)
      [[ -n "${ZSH_AI_COMMANDS_OPENAI_API_KEY:-}" ]] || { printf '%s\n' "bash-llm-replace: provider=openai but ZSH_AI_COMMANDS_OPENAI_API_KEY not set" >&2; return 1; }
      : "${ZSH_AI_COMMANDS_MODEL:=gpt-4.1-mini}"
      : "${ZSH_AI_COMMANDS_OPENAI_ENDPOINT:=https://api.openai.com/v1/responses}"
      : "${ZSH_AI_COMMANDS_OPENAI_FAST:=${ZSH_AI_COMMANDS_OPENAI_PRIORITY:-true}}"
      ;;
    openrouter)
      [[ -n "${ZSH_AI_COMMANDS_OPENROUTER_API_KEY:-}" ]] || { printf '%s\n' "bash-llm-replace: provider=openrouter but ZSH_AI_COMMANDS_OPENROUTER_API_KEY not set" >&2; return 1; }
      : "${ZSH_AI_COMMANDS_MODEL:=openai/gpt-oss-120b:nitro}"
      ;;
    *)
      printf 'bash-llm-replace: unknown provider %s\n' "$ZSH_AI_COMMANDS_PROVIDER" >&2
      return 1
      ;;
  esac
}

__bash_llm_build_request() {
  local sys_prompt="$1" user_query="$2"
  __bash_llm_headers=()

  case "$ZSH_AI_COMMANDS_PROVIDER" in
    gemini)
      __bash_llm_url="https://generativelanguage.googleapis.com/v1beta/models/${ZSH_AI_COMMANDS_MODEL}:generateContent?key=${ZSH_AI_COMMANDS_GEMINI_API_KEY}"
      __bash_llm_headers=("Content-Type: application/json" "Accept: application/json")
      __bash_llm_body="$(jq -n --arg sys "$sys_prompt" --arg user "$user_query" '{
        system_instruction: { parts: { text: $sys } },
        contents: [{ role: "user", parts: { text: $user } }],
        generationConfig: { maxOutputTokens: 512, temperature: 0.2 }
      }')" || return 1
      ;;
    openai)
      local service_tier=auto
      [[ "$ZSH_AI_COMMANDS_OPENAI_FAST" == true ]] && service_tier=fast
      __bash_llm_url="$ZSH_AI_COMMANDS_OPENAI_ENDPOINT"
      __bash_llm_headers=("Content-Type: application/json" "Authorization: Bearer $ZSH_AI_COMMANDS_OPENAI_API_KEY")
      __bash_llm_body="$(jq -n \
        --arg model "$ZSH_AI_COMMANDS_MODEL" \
        --arg reasoning_effort none \
        --arg sys "$sys_prompt" \
        --arg user "$user_query" \
        --arg tier "$service_tier" \
        '{
          model: $model,
          reasoning: { effort: $reasoning_effort },
          instructions: $sys,
          input: $user,
          max_output_tokens: 512,
          service_tier: $tier
        }')" || return 1
      ;;
    openrouter)
      local reasoning='{"effort":"low"}'
      [[ "$ZSH_AI_COMMANDS_MODEL" == *qwen* ]] && reasoning='{"enabled":false}'
      __bash_llm_url='https://openrouter.ai/api/v1/chat/completions'
      __bash_llm_headers=("Content-Type: application/json" "Authorization: Bearer $ZSH_AI_COMMANDS_OPENROUTER_API_KEY")
      __bash_llm_body="$(jq -n \
        --arg model "$ZSH_AI_COMMANDS_MODEL" \
        --arg sys "$sys_prompt" \
        --arg user "$user_query" \
        --argjson reasoning "$reasoning" \
        '{
          model: $model,
          reasoning: $reasoning,
          messages: [
            { role: "system", content: $sys },
            { role: "user", content: $user }
          ],
          max_tokens: 512,
          temperature: 0.2
        }')" || return 1
      ;;
  esac
}

__bash_llm_parse_response() {
  local resp_file="$1"

  case "$ZSH_AI_COMMANDS_PROVIDER" in
    gemini)
      jq -r '.candidates[0].content.parts | map(.text // "") | join("\n")' "$resp_file" 2>/dev/null
      ;;
    openai)
      jq -r '[.output[]? | select(.type == "message") | .content[]? | select(.type == "output_text") | .text] | join("\n")' "$resp_file" 2>/dev/null
      ;;
    openrouter)
      jq -r '.choices[0].message.content // empty' "$resp_file" 2>/dev/null
      ;;
  esac
}

__bash_llm_clean_command() {
  local raw cleaned
  raw="$(cat)"

  [[ -n "${raw//[[:space:]]/}" ]] || return 0

  if grep -q '```' <<<"$raw"; then
    cleaned="$(awk '
      /^[[:space:]]*```[[:alnum:]_-]*[[:space:]]*$/ {
        if (state == 0) { state = 1; next }
        if (state == 1) { state = 2; next }
        next
      }
      state == 1 { print }
    ' <<<"$raw")"
    if [[ -n "$cleaned" ]]; then
      __bash_llm_flatten_command <<<"$cleaned"
      return 0
    fi
  fi

  cleaned="$(grep -vE '^[[:space:]]*(Here|This|You|Note|Sure|I |The |To |It |If |For |Or |As |By |In |An |A |Of )' <<<"$raw")"
  [[ -n "$cleaned" ]] || cleaned="$raw"
  __bash_llm_flatten_command <<<"$cleaned"
}

__bash_llm_flatten_command() {
  awk '
    { raw = (NR == 1 ? $0 : raw "\n" $0) }
    END {
      n = split(raw, lines, "\n")
      for (i = 1; i <= n; i++) {
        line = lines[i]
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (i < n) {
          bs = 0
          j = length(line)
          while (j > 0 && substr(line, j, 1) == "\\") { bs++; j-- }
          if (bs % 2 == 1) {
            line = substr(line, 1, length(line) - 1)
            sub(/[[:space:]]+$/, "", line)
          }
        }
        if (line == "") continue
        out = out (out == "" ? "" : " ") line
      }
      print out
    }
  ' | sed -E 's/^[[:space:]]*```[[:space:]]*//; s/[[:space:]]*```[[:space:]]*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

__bash_llm_replace() {
  local original_query="${READLINE_LINE#AI_ASK: }"
  local sys raw cmd resp_file ret

  if [[ -z "${original_query//[[:space:]]/}" ]]; then
    printf '\nbash-llm-replace: empty prompt\n' >&2
    return 0
  fi

  __bash_llm_resolve_config || return 0
  sys="$(__bash_llm_system_prompt)"
  __bash_llm_build_request "$sys" "$original_query" || return 0

  resp_file="$(mktemp -t bashllmresp.XXXXXX)" || return 0
  printf '\nbash-llm-replace: generating...\n' >&2

  local -a curl_args
  curl_args=("--silent" "--max-time" "30" "$__bash_llm_url")
  local header
  for header in "${__bash_llm_headers[@]}"; do
    curl_args+=("-H" "$header")
  done
  curl_args+=("-d" "$__bash_llm_body")

  curl "${curl_args[@]}" >"$resp_file"
  ret=$?
  if (( ret != 0 )); then
    printf 'bash-llm-replace: curl failed (exit %d)\n' "$ret" >&2
    [[ "${ZSH_AI_COMMANDS_DEBUG:-false}" == true ]] && printf '%s\n' "$resp_file" >&2 || rm -f "$resp_file"
    return 0
  fi

  raw="$(__bash_llm_parse_response "$resp_file")"
  if [[ -z "$raw" || "$raw" == null ]]; then
    printf 'bash-llm-replace: %s API error' "$ZSH_AI_COMMANDS_PROVIDER" >&2
    if [[ "${ZSH_AI_COMMANDS_DEBUG:-false}" == true ]]; then
      printf ' (response: %s)\n' "$resp_file" >&2
    else
      printf '\n' >&2
      rm -f "$resp_file"
    fi
    return 0
  fi

  cmd="$(printf '%s\n' "$raw" | __bash_llm_clean_command)"
  if [[ -z "$cmd" ]]; then
    printf 'bash-llm-replace: empty command after parsing\n' >&2
    [[ "${ZSH_AI_COMMANDS_DEBUG:-false}" == true ]] && printf '%s\n' "$resp_file" >&2 || rm -f "$resp_file"
    return 0
  fi

  [[ "${ZSH_AI_COMMANDS_DEBUG:-false}" == true ]] && printf '%s\n' "$resp_file" >&2 || rm -f "$resp_file"
  READLINE_LINE="$cmd"
  READLINE_POINT=${#READLINE_LINE}
}

: "${ZSH_AI_COMMANDS_HOTKEY:=\C-o}"
bind -x "\"$ZSH_AI_COMMANDS_HOTKEY\": __bash_llm_replace"
