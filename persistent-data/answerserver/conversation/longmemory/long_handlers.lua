-- ./conversation/longmemory/long_handlers.lua
-- Long-memory chat: forward each turn to AnswerBank -> RAG -> Grok
-- and keep a compact Q+A history on the session.

local HISTORY_VAR = "CHAT_HISTORY"
local MAX_TURNS = 8
local ASK_SYSTEMS = { "AnswerBank", "RAG", "Grok" }

local function get_history(task_utils)
  local history = task_utils:get_session_variable(HISTORY_VAR)
  if history == nil or history == "" then
    return ""
  end
  return history
end

local function append_history(task_utils, question, answer)
  local history = get_history(task_utils)
  local turn = question .. "+" .. (answer or "")
  if history == "" then
    history = turn
  else
    history = history .. "+" .. turn
  end

  -- keep only the last MAX_TURNS Q+A pairs (2 fields each, joined by +)
  local parts = {}
  for part in string.gmatch(history, "[^+]+") do
    table.insert(parts, part)
  end
  local max_parts = MAX_TURNS * 2
  if #parts > max_parts then
    local start = #parts - max_parts + 1
    local trimmed = {}
    for i = start, #parts do
      table.insert(trimmed, parts[i])
    end
    history = table.concat(trimmed, "+")
  end

  task_utils:set_session_variable(HISTORY_VAR, history)
  return history
end

local function first_answer(results)
  if results == nil then
    return nil
  end
  if type(results) == "string" and results ~= "" then
    return results
  end
  if type(results) == "table" then
    local first = results[1] or results.answer or results.text
    if type(first) == "table" then
      return first.answer or first.text or first.response
    end
    return first
  end
  return nil
end

local function ask_systems(task_utils, question, systems)
  local composed = question
  local history = get_history(task_utils)
  if history ~= "" then
    -- OpenText Find-chat convention: prior turns joined with '+'
    composed = history .. "+" .. question
  end

  local results = task_utils:ask(composed, systems)
  local answer = first_answer(results)
  if answer == nil or answer == "" then
    answer = "I could not find an answer in AnswerBank, RAG, or Grok."
  end
  append_history(task_utils, question, answer)
  task_utils:set_response(answer)
end

function ask_answer_server(task_utils)
  local question = task_utils:get_user_text()
  ask_systems(task_utils, question, ASK_SYSTEMS)
end

function ask_answerbank(task_utils)
  ask_systems(task_utils, task_utils:get_user_text(), { "AnswerBank" })
end

function ask_rag(task_utils)
  ask_systems(task_utils, task_utils:get_user_text(), { "RAG" })
end

function ask_grok(task_utils)
  ask_systems(task_utils, task_utils:get_user_text(), { "Grok" })
end

function reset_memory(task_utils)
  task_utils:set_session_variable(HISTORY_VAR, "")
end