-- Copyright (C) Mashape, Inc.

local http = require "socket.http"
local url = require "socket.url"
local ltn12 = require "ltn12"
local cjson = require "cjson"

local _M = {}

-- Builds a querystring from a table, separated by `&`
-- @param tab The key/value parameters
-- @param key The parent key if the value is multi-dimensional (optional)
-- @return a string representing the built querystring
local function build_query(tab, key)
  if ngx then
    return ngx.encode_args(tab)
  else
    local query = {}
    local keys = {}

    for k in pairs(tab) do
      keys[#keys+1] = k
    end

    table.sort(keys)

    for _,name in ipairs(keys) do
      local value = tab[name]
      if key then
        name = string.format("%s[%s]", tostring(key), tostring(name))
      end
      if type(value) == "table" then
        query[#query+1] = build_query(value, name)
      else
        local value = tostring(value)
        if value ~= "" then
          query[#query+1] = string.format("%s=%s", name, value)
        else
          query[#query+1] = name
        end
      end
    end

    return table.concat(query, "&")
  end
end

function _M.get_utc()
  return os.time(os.date("!*t", os.time()))
end

function _M.table_size(t)
  local res = 0
  for _,_ in pairs(t) do
    res = res + 1
  end
  return res
end

function _M.show_response(status, message)
  ngx.header["X-Apenode-Version"] = configuration.version
  ngx.status = status
  if (type(message) == "table") then
    ngx.print(cjson.encode(message))
  else
    ngx.print(cjson.encode({message = message}))
  end
  ngx.exit(status)
end

function _M.show_error(status, message)
  ngx.ctx.error = true
  _M.show_response(status, message)
end

function _M.success(message)
  _M.show_response(200, message)
end

function _M.created(message)
  _M.show_response(201, message)
end

function _M.not_found(message)
  message = message or "Not found"
  _M.show_error(404, message)
end

function _M.create_timer(func, data)
  local ok, err = ngx.timer.at(0, func, data)
  if not ok then
    ngx.log(ngx.ERR, "failed to create timer: ", err)
    return
  end
end

function _M.read_file(path)
  local contents = nil
  local file = io.open(path, "rb")
  if file then
    contents = file:read("*all")
    file:close()
  end
  return contents
end

function _M.write_to_file(path, value)
  local file = io.open(path, "w")
  file:write(value)
  file:close()
end

local epoch = {year=1970, month=1, day=1, hour=0, min=0, sec=0, isdst=false }
local function gmtime(t)
   t.isdst =  false
   return os.time(t) - os.time(epoch)
end

function _M.get_timestamps(now)
  local _now = math.floor(now) -- Convert milliseconds to seconds. Milliseconds in openresty are in decimal places
  local date = os.date("!*t", _now) -- In milliseconds

  local second = _now
  date.sec = 0
  local minute = gmtime(date)
  date.min = 0
  local hour = gmtime(date)
  date.hour = 0
  local day = gmtime(date)
  date.day = 1
  local month = gmtime(date)
  date.month = 1
  local year = gmtime(date)

  return {second=second * 1000, minute=minute * 1000, hour=hour * 1000,day=day * 1000, month=month * 1000, year=year * 1000}
end

local function http_call(options)
  -- Set Host header accordingly
  if not options.headers["host"] then
    local parsed_url = url.parse(options.url)
    local port_segment = ""
    if parsed_url.port then
      port_segment = ":" .. parsed_url.port
    end
    options.headers["host"] = parsed_url.host .. port_segment
  end

  -- Returns: response, code, headers
  local resp = {}
  options.sink = ltn12.sink.table(resp)

  local r, code, headers = http.request(options)
  return resp[1], code, headers
end

function _M.get(url, querystring, headers)
  if not headers then headers = {} end

  if querystring then
    url = string.format("%s?%s", url, build_query(querystring))
  end

  return http_call {
    method = "GET",
    url = url,
    headers = headers
  }
end

function _M.delete(url, querystring, headers)
  if not headers then headers = {} end

  if querystring then
    url = string.format("%s?%s", url, build_query(querystring))
  end

  return http_call {
    method = "DELETE",
    url = url,
    headers = headers
  }
end

function _M.post(url, form, headers)
  if not headers then headers = {} end
  if not form then form = {} end

  local body = build_query(form)
  headers["content-length"] = string.len(body)
  headers["content-type"] = "application/x-www-form-urlencoded"

  return http_call {
    method = "POST",
    url = url,
    headers = headers,
    source = ltn12.source.string(body)
  }
end

return _M
