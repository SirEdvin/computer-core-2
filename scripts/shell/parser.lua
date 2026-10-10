-- Literal shell tokens only. Never evaluates expansions, Lua or shell operators.
local M={max_bytes=8192,max_tokens=32}
local whitespace={[' ']=true,['\t']=true,['\r']=true,['\n']=true,['\v']=true,['\f']=true}
local operators={['|']=true,['>']=true,['<']=true,[';']=true,['`']=true,['$']=true,['&']=true}
function M.tokens(line,partial)
  if type(line)~='string' or #line>M.max_bytes or line:find('%z') then return nil,'invalid command text' end
  local out,parts={},{}
  local quote,start=nil,nil
  local i=1
  local function finish(last)
    if not start then return true end
    if #out>=M.max_tokens then return false end
    out[#out+1]={text=table.concat(parts),first=start,last=last,quote=quote}
    start,parts=nil,{}
    return true
  end
  while i<=#line do
    local byte=line:sub(i,i)
    if not quote and whitespace[byte] then
      if not finish(i-1) then return nil,'too many arguments' end
    else
      start=start or i
      if byte=='\\' then
        i=i+1
        if i>#line then
          if not partial then return nil,'unfinished escape' end
          parts[#parts+1]='\\'
        else
          local escaped=line:sub(i,i)
          parts[#parts+1]=escaped=='n' and '\n' or escaped=='r' and '\r' or escaped=='t' and '\t' or escaped
        end
      elseif byte=='"' or byte=="'" then
        if quote==byte then quote=nil
        elseif not quote then quote=byte
        else parts[#parts+1]=byte end
      elseif not quote and operators[byte] then return nil,'unsupported shell syntax'
      else parts[#parts+1]=byte end
    end
    i=i+1
  end
  if quote and not partial then return nil,'unterminated quoted argument' end
  if not finish(#line) then return nil,'too many arguments' end
  if partial and (#line==0 or whitespace[line:sub(-1)] and not quote) then
    out[#out+1]={text='',first=#line+1,last=#line,quote=nil}
  end
  return out
end
function M.arguments(line,count)
  local tokens,err=M.tokens(line)
  if not tokens then return nil,err end
  if #tokens~=count then return nil,'expected '..count..' argument(s)' end
  local args={}
  for i=1,#tokens do args[i]=tokens[i].text end
  return args
end
function M.quote(text)
  -- Escaping is bounded by the existing path/command byte caps.
  return '"'..text:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')..'"'
end
return M
