-- Knowledge Discovery chat.
-- Answer a question (Grok RAG over KD Content) and stay idle.
-- Finish a task and stay idle. The next utterance is a new question or a new task.

local dkjson = require("dkjson")
local idol_aci = require("idol_aci")

MAX_LISTED_SOURCES = 3
ANSWER_SERVER_HOST = "answerserver.idoldemos.net"
ANSWER_SERVER_PORT = 12000
RAG_SYSTEM_NAME = "Grok"
DEFAULT_DATABASES = "*"

-- ---------------------------------------------------------------------------
-- Logging / session helpers
-- ---------------------------------------------------------------------------

function write_log(function_name, message)
  local log = get_log("application")
  log:write_line(log_level_normal(), "[kdchat] " .. function_name .. "(): " .. tostring(message or ""))
end

function session_var(taskUtils, name, default)
  local value = taskUtils:getSessionVar(name)
  if value == nil or value == "" then
    return default
  end
  return value
end

function unescape_html(str)
  if not str then
    return ""
  end
  local map = {
    ["&lt;"] = "<",
    ["&gt;"] = ">",
    ["&amp;"] = "&",
    ["&quot;"] = '"',
    ["&apos;"] = "'"
  }
  return (string.gsub(str, "(&%a+;)", function(entity)
    return map[entity] or entity
  end))
end

function strip_html(text)
  if not text then
    return ""
  end
  text = string.gsub(text, "<[^>]*>", "")
  text = string.gsub(text, "&[^;]*;", "")
  text = string.gsub(text, "%s+", " ")
  return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

function html_escape(text)
  if not text then
    return ""
  end
  text = string.gsub(text, "&", "&amp;")
  text = string.gsub(text, "<", "&lt;")
  text = string.gsub(text, ">", "&gt;")
  return text
end

function wrap_html(inner)
  return "<div style='font-family: sans-serif;'>" .. inner .. "</div>"
end

function speak(taskUtils, html)
  taskUtils:setPrompts({ LuaUserPrompt:new(wrap_html(html)) })
end

function current_db_label(match)
  if not match or match == "" or match == "*" then
    return "all databases"
  end
  return match
end

function initialize_session(taskUtils)
  -- UI can pre-seed SECURITY_INFO, SELECTED_DATABASE, LAST_ANSWER via ManageResources.
  -- KEEP_CONTEXT=1 means "continue from the Answer panel" — do not wipe those vars.
  local keep = session_var(taskUtils, "KEEP_CONTEXT", "")
  if keep == "1" then
    taskUtils:setSessionVar("KEEP_CONTEXT", "")
    if session_var(taskUtils, "CHAT_HISTORY", "") == "" then
      taskUtils:setSessionVar("CHAT_HISTORY", "")
    end
    local db = session_var(taskUtils, "SELECTED_DATABASE", DEFAULT_DATABASES)
    if session_var(taskUtils, "SELECTED_DATABASE_LABEL", "") == "" then
      taskUtils:setSessionVar("SELECTED_DATABASE_LABEL", current_db_label(db))
    end
    local locked = session_var(taskUtils, "LOCKED_REFERENCES", "")
    write_log("initialize_session", "Kept seeded context; SELECTED_DATABASE=" .. db ..
      " LOCKED_REFERENCES=" .. locked)
    return
  end

  taskUtils:setSessionVar("CHAT_HISTORY", "")
  taskUtils:setSessionVar("SELECTED_DATABASE", DEFAULT_DATABASES)
  taskUtils:setSessionVar("SELECTED_DATABASE_LABEL", current_db_label(DEFAULT_DATABASES))
  taskUtils:setSessionVar("LAST_ANSWER", "")
  taskUtils:setSessionVar("LAST_SOURCES", "")
  taskUtils:setSessionVar("LOCKED_REFERENCES", "")
  taskUtils:setSessionVar("AVAILABLE_DATABASES", "")
  write_log("initialize_session", "Session reset; searching all KD databases.")
end

function locked_refs(taskUtils)
  return split_csv(session_var(taskUtils, "LOCKED_REFERENCES", ""))
end

function clear_locked_references(taskUtils)
  taskUtils:setSessionVar("LOCKED_REFERENCES", "")
  write_log("clear_locked_references", "Source lock cleared")
end

function scope_label(taskUtils)
  local refs = locked_refs(taskUtils)
  if #refs > 0 then
    return tostring(#refs) .. " source document" .. (#refs == 1 and "" or "s") .. " from the previous answer"
  end
  return current_db_label(session_var(taskUtils, "SELECTED_DATABASE", DEFAULT_DATABASES))
end

function greet(taskUtils)
  speak(taskUtils,
    "Hello. I search your Knowledge Discovery databases and I can switch scope or list sources, then I move on.<br>" ..
    "Currently searching: <strong>" .. html_escape(scope_label(taskUtils)) .. "</strong>. Ask a question, or say <strong>help</strong>.")
end

function show_help(taskUtils)
  speak(taskUtils,
    "I answer questions from KD, finish the task, and wait for the next one.<br><ul>" ..
    "<li>Ask anything — I retrieve from <strong>" .. html_escape(scope_label(taskUtils)) .. "</strong> via Grok RAG.</li>" ..
    "<li>Continued from an Answer: follow-ups stay inside those source documents until you say <strong>search all</strong>.</li>" ..
    "<li><strong>what databases</strong> — list searchable KD databases.</li>" ..
    "<li><strong>use database xECM</strong> — persist a filter (comma-separated names, or <strong>all</strong>).</li>" ..
    "<li><strong>search in FTA_Website: what is a tax assessment?</strong> — one-shot filter, does not change the session.</li>" ..
    "<li><strong>search all</strong> — clear the filter and any source lock.</li>" ..
    "<li><strong>sources</strong> — citations from the last answer.</li>" ..
    "<li><strong>start again</strong> / <strong>cancel</strong> — reset or abandon a task.</li>" ..
    "</ul>After every answer or task I am idle. Just continue.")
end

-- ---------------------------------------------------------------------------
-- Database listing / selection
-- ---------------------------------------------------------------------------

function fetch_databases(taskUtils)
  local databases = idol_aci.list_searchable_databases(false)
  local names = idol_aci.database_names(databases)
  taskUtils:setSessionVar("AVAILABLE_DATABASES", table.concat(names, ","))
  return databases, names
end

function format_database_list(databases)
  if not databases or #databases == 0 then
    return "<p>I could not list any searchable databases right now.</p>"
  end
  local lines = { "<p>Searchable Knowledge Discovery databases:</p><ul>" }
  for _, db in ipairs(databases) do
    local count
    if db.documents and db.documents >= 0 then
      count = tostring(db.documents) .. " documents"
    else
      count = "count unknown"
    end
    table.insert(lines, "<li><strong>" .. html_escape(db.name) .. "</strong> (" .. count .. ")</li>")
  end
  table.insert(lines, "</ul>")
  return table.concat(lines)
end

function list_databases(taskUtils)
  local databases = fetch_databases(taskUtils)
  local scope = current_db_label(session_var(taskUtils, "SELECTED_DATABASE", DEFAULT_DATABASES))
  local html = format_database_list(databases) ..
    "<p>Currently searching: <strong>" .. html_escape(scope) .. "</strong>.</p>" ..
    "<p>Say <strong>use database xECM</strong> or <strong>search all</strong>.</p>"
  local names = idol_aci.database_names(databases)
  table.insert(names, "all")
  taskUtils:setPrompts({ LuaUserPrompt:new(wrap_html(html), names, {}) })
end

function prepare_database_selection(taskUtils)
  -- Cache the live list only. Do not setPrompts here — that would consume
  -- the trigger turn ("use database FTA_Website") before the requirement
  -- validator can fill SELECTED_DATABASE from the same utterance.
  local databases = fetch_databases(taskUtils)
  local list = format_database_list(databases)
  taskUtils:setSessionVar("DATABASE_LIST_PROMPT", list)
end

function is_all_databases(text)
  local t = string.lower(text or "")
  t = (string.gsub(t, "^%s*(.-)%s*$", "%1"))
  if t == "*" or t == "all" or t == "everything" then
    return true
  end
  if string.find(t, "all databases", 1, true) then
    return true
  end
  if string.find(t, "search all", 1, true) then
    return true
  end
  if string.find(t, "use all", 1, true) then
    return true
  end
  return false
end

function match_databases_from_text(input, available_names)
  if not input or input == "" then
    return nil
  end
  if is_all_databases(input) then
    return "*"
  end

  local lower = string.lower(input)
  local matched = {}
  local seen = {}
  for _, name in ipairs(available_names or {}) do
    if string.find(lower, string.lower(name), 1, true) and not seen[name] then
      table.insert(matched, name)
      seen[name] = true
    end
  end
  if #matched == 0 then
    return nil
  end
  return table.concat(matched, ",")
end

function split_csv(value)
  local items = {}
  for part in string.gmatch(value or "", "([^,]+)") do
    part = string.gsub(part, "^%s*(.-)%s*$", "%1")
    if part ~= "" then
      table.insert(items, part)
    end
  end
  return items
end

function database_validator(input, taskUtils)
  local available = split_csv(session_var(taskUtils, "AVAILABLE_DATABASES", ""))
  if #available == 0 then
    local _, names = fetch_databases(taskUtils)
    available = names
  end
  local match = match_databases_from_text(input, available)
  if match then
    return match
  end
  local hint = table.concat(available, ", ")
  if hint == "" then
    hint = "xECM, FTA_Website, SharePoint, WRC, CAD"
  end
  taskUtils:setTaskVar("VALIDATION_RESPONSE",
    "I don't recognize that database. Try one of: " .. hint .. " — or say all.")
end

function set_validation_response(taskUtils)
  local response = taskUtils:getTaskVar("VALIDATION_RESPONSE")
  if response ~= nil then
    taskUtils:setPrompts({ LuaUserPrompt:new(wrap_html("<p>" .. html_escape(response) .. "</p>")) })
    taskUtils:clearTaskVar("VALIDATION_RESPONSE")
  end
end

function confirm_database_selection(taskUtils)
  local match = taskUtils:getTaskVar("DATABASE_CHOICE")
  if not match or match == "" then
    match = DEFAULT_DATABASES
  end
  local label = current_db_label(match)
  taskUtils:setSessionVar("SELECTED_DATABASE", match)
  taskUtils:setSessionVar("SELECTED_DATABASE_LABEL", label)
  clear_locked_references(taskUtils)
  write_log("confirm_database_selection", "SELECTED_DATABASE=" .. match)
end

function search_all_databases(taskUtils)
  taskUtils:setSessionVar("SELECTED_DATABASE", DEFAULT_DATABASES)
  taskUtils:setSessionVar("SELECTED_DATABASE_LABEL", current_db_label(DEFAULT_DATABASES))
  clear_locked_references(taskUtils)
  write_log("search_all_databases", "Filter cleared")
end

function show_last_sources(taskUtils)
  local raw = session_var(taskUtils, "LAST_SOURCES", "")
  if raw == "" then
    speak(taskUtils, "I do not have sources from a previous answer in this session. Ask a question first.")
    return
  end
  local items = split_csv(raw)
  local sources = {}
  for _, ref in ipairs(items) do
    table.insert(sources, { ref = ref, title = "" })
  end
  sources = resolve_source_titles(sources, session_var(taskUtils, "SECURITY_INFO", ""))
  local html = "<p>Sources from the last answer:</p><ul>"
  for _, src in ipairs(sources) do
    html = html .. source_list_item(src)
  end
  html = html .. "</ul>"
  speak(taskUtils, html)
end

-- ---------------------------------------------------------------------------
-- Ask / RAG
-- ---------------------------------------------------------------------------

function extract_answer_text(xml)
  if not xml or xml == "" then
    write_log("extract_answer_text", "empty Ask response")
    return nil
  end
  -- send_aci_action returns XML (not simplejson). Prefer <answer><text>.
  local inner = string.match(xml, "<answer[^>]*>.-<text[^>]*>(.-)</text>") or
                string.match(xml, "<text[^>]*>(.-)</text>") or
                string.match(xml, "<autn:text[^>]*>(.-)</autn:text>")
  if not inner then
    write_log("extract_answer_text", "no <text> in Ask response (" ..
      tostring(#xml) .. " bytes): " .. string.sub(xml, 1, 360))
    return nil
  end
  local text = string.match(inner, "<!%[CDATA%[(.-)%]%]%>") or inner
  text = unescape_html(text)
  text = string.gsub(text, "^%s*(.-)%s*$", "%1")
  if text == "" then
    return nil
  end
  return text
end

function extract_sources(xml, security_info)
  local sources = {}
  if not xml or xml == "" then
    return sources
  end
  for tag in string.gmatch(xml, "<source%s+[^>]+>") do
    local ref = string.match(tag, 'ref="([^"]*)"')
    local title = string.match(tag, 'title="([^"]*)"') or ""
    local database = string.match(tag, 'database="([^"]*)"') or ""
    if ref and ref ~= "" then
      table.insert(sources, { ref = ref, title = title, database = database })
    end
  end
  if #sources == 0 then
    for ref in string.gmatch(xml, '<source[^>]-ref="([^"]+)"') do
      table.insert(sources, { ref = ref, title = "", database = "" })
    end
  end
  return resolve_source_titles(sources, security_info)
end

function extract_source_refs(xml)
  local refs = {}
  for _, src in ipairs(extract_sources(xml)) do
    table.insert(refs, src.ref)
  end
  return refs
end

function usable_title(title, ref)
  if not title or title == "" or title == "(No title)" then
    return false
  end
  if ref and string.lower(title) == string.lower(ref) then
    return false
  end
  if string.match(title, "^[/\\]") or string.match(title, "^[A-Za-z]:[\\/]") then
    return false
  end
  return true
end

function pretty_title_from_ref(ref)
  if not ref or ref == "" then
    return "Source"
  end
  local ot = string.match(ref, "^OpenText:(%d+)")
  if ot then
    return "Document " .. ot
  end
  local base = string.match(ref, "([^/\\]+)$") or ref
  base = string.gsub(base, "%.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]?[A-Za-z0-9]?$", "")
  base = string.gsub(base, "[_+]+", " ")
  base = string.gsub(base, "%s+", " ")
  base = string.gsub(base, "^%s*(.-)%s*$", "%1")
  return base ~= "" and base or "Source"
end

function lookup_doc(docs, ref)
  if not docs or not ref then
    return nil
  end
  if docs[ref] then
    return docs[ref]
  end
  local want = string.lower(ref)
  for key, doc in pairs(docs) do
    if string.lower(key) == want then
      return doc
    end
  end
  return nil
end

function resolve_source_titles(sources, security_info)
  local missing = {}
  for _, src in ipairs(sources) do
    if not usable_title(src.title, src.ref) or not src.url then
      table.insert(missing, src.ref)
    end
  end
  if #missing > 0 then
    local docs = idol_aci.documents_for_references(missing, security_info)
    for _, src in ipairs(sources) do
      local doc = lookup_doc(docs, src.ref)
      if doc then
        if usable_title(doc.title, src.ref) then
          src.title = doc.title
        end
        if doc.database and doc.database ~= "" then
          src.database = doc.database
        end
        if doc.url then
          src.url = doc.url
        end
      end
    end
  end
  for _, src in ipairs(sources) do
    if not usable_title(src.title, src.ref) then
      src.title = pretty_title_from_ref(src.ref)
    end
    if not src.url then
      src.url = idol_aci.document_url(src.ref, src.database, nil, nil)
    end
  end
  return sources
end

function source_list_item(src)
  local ref = src.ref or src
  local title = src.title
  if type(src) ~= "table" then
    src = { ref = ref, title = title }
  end
  if not usable_title(title, ref) then
    title = pretty_title_from_ref(ref)
  end
  local href = src.url or idol_aci.document_url(ref, src.database, nil, nil)
  if href then
    return "<li><a href='" .. html_escape(href) ..
      "' target='_blank' rel='noopener noreferrer' data-ref='" .. html_escape(ref) ..
      "' data-database='" .. html_escape(src.database or "") .. "'>" ..
      html_escape(title) .. "</a></li>"
  end
  return "<li>" .. html_escape(title) .. "</li>"
end

function parse_inline_search(question)
  local db, rest = string.match(question, "^[Ss]earch%s+in%s+([%w_]+)%s*[:%-]%s*(.+)$")
  if db and rest then
    return db, rest
  end
  db, rest = string.match(question, "^[Ii]n%s+([%w_]+)%s*[,:]%s+(.+)$")
  if db and rest then
    return db, rest
  end
  return nil, question
end

function build_ask_parameters(question, database_match, security_info, match_refs)
  local params = {
    Text = question,
    SystemNames = RAG_SYSTEM_NAME,
    MaxResults = 1,
    AnyLanguage = "true"
  }
  -- Continue-from-answer: retrieve only the cited documents. Do not also send
  -- DatabaseMatch — that can exclude the DB that actually holds the reference.
  -- Never use MatchReference here: file-path and http(s) DREREFERENCEs are
  -- rejected ("reference does not exist") and Converse then returns the
  -- "couldn't find anything relevant" prompt.
  if match_refs and #match_refs > 0 then
    params.FieldText = idol_aci.fieldtext_match_references(match_refs)
    local n = #match_refs
    if n < 2 then
      n = 2
    elseif n > 20 then
      n = 20
    end
    params.MaxResults = n
    params.Summary = "Context"
    params.TotalCharacters = "50000"
  elseif database_match and database_match ~= "" and database_match ~= "*" then
    params.DatabaseMatch = database_match
  end
  if security_info and security_info ~= "" then
    local customization_data = {
      { system_name = RAG_SYSTEM_NAME, security_info = security_info }
    }
    params.CustomizationData = dkjson.encode(customization_data)
  end
  return params
end

function ask_grok(question, database_match, security_info, match_refs)
  local params = build_ask_parameters(question, database_match, security_info, match_refs)
  local ssl_parameters = { SSLMethod = "Negotiate" }
  local lock_note = ""
  if match_refs and #match_refs > 0 then
    if params.FieldText then
      lock_note = " FieldText=" .. tostring(params.FieldText)
    else
      lock_note = " MatchReference=" .. table.concat(match_refs, " | ")
    end
  end
  write_log("ask_grok", "DatabaseMatch=" .. tostring(database_match or "*") ..
    lock_note .. " question=" .. question)
  local ok, output = pcall(
    send_aci_action,
    ANSWER_SERVER_HOST,
    ANSWER_SERVER_PORT,
    "ask",
    params,
    120000,
    1,
    ssl_parameters
  )
  if not ok then
    write_log("ask_grok", "send_aci_action failed: " .. tostring(output))
    return nil, nil
  end
  return extract_answer_text(output), extract_sources(output, security_info)
end

function present_answer(taskUtils, answer_text, sources, question, database_match)
  local searched = scope_label(taskUtils)
  if not answer_text or answer_text == "" then
    speak(taskUtils, "<p>Sorry, I couldn't find anything relevant for <strong>" ..
      html_escape(question) .. "</strong> in <strong>" ..
      html_escape(searched) .. "</strong>.</p>")
    taskUtils:setSessionVar("LAST_ANSWER", "")
    taskUtils:setSessionVar("LAST_SOURCES", "")
    return
  end

  local html = answer_text
  html = html .. "<p style='margin-top:10px;font-size:smaller;color:#555;'>Searched: " ..
    html_escape(searched) .. "</p>"

  if sources and #sources > 0 then
    html = html .. "<ul style='margin-top:8px;'>"
    local stored = {}
    for i, src in ipairs(sources) do
      if i > MAX_LISTED_SOURCES then
        break
      end
      local ref = src.ref or src
      html = html .. source_list_item(src)
      table.insert(stored, ref)
    end
    html = html .. "</ul>"
    taskUtils:setSessionVar("LAST_SOURCES", table.concat(stored, ","))
  else
    taskUtils:setSessionVar("LAST_SOURCES", "")
  end

  speak(taskUtils, html)
  taskUtils:setSessionVar("LAST_ANSWER", strip_html(answer_text))
end

function ask_kd(taskUtils)
  local raw = taskUtils:getUserText()
  if not raw or string.match(raw, "^%s*$") then
    speak(taskUtils, "<p>Ask a question, or say <strong>help</strong>.</p>")
    return
  end

  local inline_db, question = parse_inline_search(raw)
  local database_match
  if inline_db then
    database_match = inline_db
    write_log("ask_kd", "One-shot DatabaseMatch=" .. inline_db)
  else
    database_match = session_var(taskUtils, "SELECTED_DATABASE", DEFAULT_DATABASES)
  end

  local security_info = session_var(taskUtils, "SECURITY_INFO", "")
  local match_refs = locked_refs(taskUtils)
  local answer_text, sources = ask_grok(question, database_match, security_info, match_refs)
  -- Locked FieldText can still return zero candidates (security, encoding).
  -- Fall back to the session database so Converse is not an empty apology.
  if (not answer_text or answer_text == "") and match_refs and #match_refs > 0 then
    write_log("ask_kd", "Locked retrieval empty; retrying DatabaseMatch=" ..
      tostring(database_match or "*"))
    answer_text, sources = ask_grok(question, database_match, security_info, nil)
  end
  present_answer(taskUtils, answer_text, sources, question, database_match)
end
