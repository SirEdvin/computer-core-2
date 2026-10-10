-- Primitive coverage only: runtime/GUI completion wiring is not yet acceptance.
local Parser=require('__computer_core_2__.scripts.shell.parser')
local Directory=require('__computer_core_2__.scripts.shell.directory')
local M={}
function M.initial(check)
  local args=assert(Parser.arguments([["a b" 'c d']],2))
  check('literal parser accepts both quoting styles',args[1]=='a b' and args[2]=='c d')
  local literal=[[both ' and " and \ and]]..'\n'
  args=assert(Parser.arguments(Parser.quote(literal),1))
  check('literal parser round trips quote backslash newline data',args[1]==literal)
  check('parser refuses executable shell operators',Parser.tokens('cat a | require b')==nil and Parser.tokens('$(os.execute())')==nil)
  local s={disk={cwd='/',fs={['/']={type='dir'},['/a']={type='file',text=''},['/z']={type='file',text=''},['/space dir']={type='dir'}}},command='cl',cursor=2}
  local function finish(job)
    for _=1,512 do if Directory.advance(s,job) then return job end end
    error('directory primitive did not finish')
  end
  local job=finish(Directory.new(s,'completion',nil,{'pwd','clear','cat','cd','help'}))
  local line,cursor=Directory.completion(job)
  check('primitive command completion uses literal fixed names',line=='clear' and cursor==5)
  s.command='cat "sp'; s.cursor=#s.command
  job=finish(Directory.new(s,'completion',nil,{})); line,cursor=Directory.completion(job)
  check('primitive quoted directory completion preserves open quote',line=='cat "space dir/' and cursor==#line)
  s.command='clear suffix'; s.cursor=2
  job=finish(Directory.new(s,'completion',nil,{'clear'})); line,cursor=Directory.completion(job)
  check('primitive mid-token completion does not duplicate existing suffix',line=='clear suffix' and cursor==2)
  job=finish(Directory.new(s,'listing','/'))
  check('bounded native merge gives stable literal directory order',#job.items==4 and job.items[1].name=='a'
    and job.items[2].name=='rom/' and job.items[3].name=='space dir/' and job.items[4].name=='z')
  check('bundled read-only data is visible without executing it',Directory.get(s.disk,'/rom/help.txt').type=='file'
    and Directory.readonly('/rom') and Directory.readonly('/rom/help.txt') and not Directory.readonly('/romance'))
end
return M
