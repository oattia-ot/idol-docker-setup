-- Thin ACI helpers for the KD chat conversation system.
-- Lists Knowledge Discovery databases from the same Content engine
-- the Grok RAG system retrieves from (content1:9200).

local M = {}

CONTENT_HOST = "content1.idoldemos.net"
CONTENT_PORT = 9200

-- Fallback if GetStatus is unreachable. Names only; document counts unknown.
KNOWN_DATABASES = {
  { name = "xECM", documents = -1, internal = false },
  { name = "FTA_Website", documents = -1, internal = false },
  { name = "SharePoint", documents = -1, internal = false },
  { name = "WRC", documents = -1, internal = false },
  { name = "CAD", documents = -1, internal = false }
}

local function write(message)
  local log = get_log("application")
  if message == nil or message == "" then
    return
  end
  log:write_line(log_level_normal(), "[kdchat/idol_aci] " .. tostring(message))
end

function M.parse_databases_xml(xml)
  local result = {}
  if not xml or xml == "" then
    return result
  end
  for block in string.gmatch(xml, "<database>(.-)</database>") do
    local name = string.match(block, "<name>(.-)</name>")
    local documents = tonumber(string.match(block, "<documents>(.-)</documents>") or "0") or 0
    local internal = string.match(block, "<internal>(.-)</internal>")
    if name and name ~= "" then
      table.insert(result, {
        name = name,
        documents = documents,
        internal = (internal == "true")
      })
    end
  end
  return result
end

function M.get_status_xml(host, port, timeout_ms, retries)
  host = host or CONTENT_HOST
  port = port or CONTENT_PORT
  timeout_ms = timeout_ms or 15000
  retries = retries or 2
  local ssl_parameters = { SSLMethod = "Negotiate" }
  write("GetStatus " .. host .. ":" .. tostring(port))
  local ok, response = pcall(send_aci_action, host, port, "GetStatus", {}, timeout_ms, retries, ssl_parameters)
  if not ok or not response or response == "" then
    write("GetStatus failed: " .. tostring(response))
    return nil
  end
  return response
end

-- Return searchable KD databases (non-internal, with documents when counts are known).
function M.list_searchable_databases(include_empty)
  local xml = M.get_status_xml()
  local databases
  if xml then
    databases = M.parse_databases_xml(xml)
  else
    write("Using hardcoded database fallback")
    databases = KNOWN_DATABASES
  end

  local result = {}
  for _, db in ipairs(databases) do
    if not db.internal then
      if include_empty or db.documents ~= 0 then
        table.insert(result, db)
      end
    end
  end

  table.sort(result, function(a, b)
    if a.documents == b.documents then
      return a.name < b.name
    end
    return (a.documents or 0) > (b.documents or 0)
  end)
  return result
end

function M.database_names(databases)
  local names = {}
  for _, db in ipairs(databases or {}) do
    table.insert(names, db.name)
  end
  return names
end

XECM_OVERVIEW =
  "https://otcs.poc058.eimdemo.com/cs/cs.exe?func=ll&objAction=overview&objId="

local function xml_field(block, tag)
  if not block or not tag then
    return ""
  end
  local value = string.match(block, "<" .. tag .. ">(.-)</" .. tag .. ">")
    or string.match(block, "<autn:" .. tag .. ">(.-)</autn:" .. tag .. ">")
  if not value then
    return ""
  end
  value = string.gsub(value, "<!%[CDATA%[(.-)%]%]%>", "%1")
  value = string.gsub(value, "^%s*(.-)%s*$", "%1")
  return value
end

-- xECM prefers NAME; CAD / websites prefer DRETITLE.
local function title_from_hit_xml(block)
  if not block or block == "" then
    return nil
  end
  local candidates = { "NAME", "DRETITLE", "TITLE", "name", "dretitle", "title" }
  for _, tag in ipairs(candidates) do
    local value = xml_field(block, tag)
    if value ~= "" then
      return value
    end
  end
  return nil
end

local function node_id_from_hit(block, reference)
  local id = xml_field(block, "NODE_ID")
  if id == "" then
    id = xml_field(block, "OBJID")
  end
  if id == "" and reference then
    id = string.match(reference, "^OpenText:(%d+)") or string.match(reference, "^(%d+)$")
  end
  return id or ""
end

function M.document_url(ref, database, node_id, final_url)
  if final_url and string.match(final_url, "^https?://") then
    return final_url
  end
  if ref and string.match(ref, "^https?://") then
    return ref
  end
  local id = node_id or ""
  if id == "" and ref then
    id = string.match(ref, "^OpenText:(%d+)") or string.match(ref, "^(%d+)$") or ""
  end
  if id ~= "" then
    local db = string.lower(database or "")
    if db == "" or db == "xecm" then
      return XECM_OVERVIEW .. id
    end
  end
  return nil
end

local function apply_security(params, security_info)
  if security_info and security_info ~= "" then
    params.SecurityInfo = security_info
  end
  return params
end

local function parse_hits_into(map, xml)
  if not xml or xml == "" then
    return
  end
  local function take(hit)
    local reference = xml_field(hit, "reference")
    if reference == "" then
      reference = xml_field(hit, "DREREFERENCE")
    end
    if reference == "" then
      return
    end
    local database = xml_field(hit, "database")
    if database == "" then
      database = xml_field(hit, "DREDBNAME")
    end
    local node_id = node_id_from_hit(hit, reference)
    local final_url = xml_field(hit, "FINAL_URL")
    map[reference] = {
      title = title_from_hit_xml(hit) or "",
      database = database,
      node_id = node_id,
      final_url = final_url,
      url = M.document_url(reference, database, node_id, final_url)
    }
  end
  local n = 0
  for hit in string.gmatch(xml, "<autn:hit>(.-)</autn:hit>") do
    take(hit)
    n = n + 1
  end
  if n == 0 then
    for hit in string.gmatch(xml, "<hit>(.-)</hit>") do
      take(hit)
    end
  end
end

local PRINT_FIELDS = "NAME,DRETITLE,TITLE,DREREFERENCE,DREDBNAME,NODE_ID,OBJID,FINAL_URL"

-- File-path DREREFERENCEs (slashes, spaces, parentheses) are rejected by
-- MatchReference / GetContent Reference. FieldText MATCH on DREREFERENCE works.
function M.reference_needs_fieldtext(ref)
  if not ref or ref == "" then
    return false
  end
  return string.find(ref, "/", 1, true)
    or string.find(ref, "\\", 1, true)
    or string.find(ref, " ", 1, true)
    or string.find(ref, "(", 1, true)
    or string.find(ref, ")", 1, true)
end

function M.references_need_fieldtext(refs)
  for _, ref in ipairs(refs or {}) do
    if M.reference_needs_fieldtext(ref) then
      return true
    end
  end
  return false
end

function M.fieldtext_escape_match_value(value)
  return (string.gsub(value or "", "([\\{},])", "\\%1"))
end

function M.fieldtext_match_references(refs)
  local escaped = {}
  for _, ref in ipairs(refs or {}) do
    if ref and ref ~= "" then
      table.insert(escaped, M.fieldtext_escape_match_value(ref))
    end
  end
  if #escaped == 0 then
    return nil
  end
  return "MATCH{" .. table.concat(escaped, ",") .. "}:DREREFERENCE"
end

-- Map DREREFERENCE → { title, database, node_id, url } via Content Query / GetContent.
function M.documents_for_references(refs, security_info)
  local map = {}
  if not refs or #refs == 0 then
    return map
  end
  local slice = {}
  for i, ref in ipairs(refs) do
    if i > 20 then
      break
    end
    table.insert(slice, ref)
  end

  local qparams = apply_security({
    Text = "*",
    Print = "Fields",
    PrintFields = PRINT_FIELDS,
    MaxResults = tostring(#slice),
    AnyLanguage = "true",
    TotalResults = "false",
    Predict = "false"
  }, security_info)
  qparams.FieldText = M.fieldtext_match_references(slice)
  write("Query documents for " .. tostring(#slice) .. " references")
  local ok, xml = pcall(
    send_aci_action,
    CONTENT_HOST,
    CONTENT_PORT,
    "Query",
    qparams,
    20000,
    2,
    { SSLMethod = "Negotiate" }
  )
  if ok then
    parse_hits_into(map, xml)
  else
    write("Title Query failed: " .. tostring(xml))
  end

  for _, ref in ipairs(slice) do
    if map[ref] and map[ref].title ~= "" then
      -- already have a title
    else
      local gparams = apply_security({
        Reference = ref,
        Print = "Fields",
        PrintFields = PRINT_FIELDS
      }, security_info)
      write("GetContent " .. ref)
      local gok, gxml = pcall(
        send_aci_action,
        CONTENT_HOST,
        CONTENT_PORT,
        "GetContent",
        gparams,
        15000,
        1,
        { SSLMethod = "Negotiate" }
      )
      if gok then
        parse_hits_into(map, gxml)
      else
        write("GetContent failed: " .. tostring(gxml))
      end
    end
  end
  return map
end

-- Back-compat: title string map.
function M.titles_for_references(refs, security_info)
  local docs = M.documents_for_references(refs, security_info)
  local map = {}
  for ref, doc in pairs(docs) do
    if doc.title and doc.title ~= "" then
      map[ref] = doc.title
    end
  end
  return map
end

return M
