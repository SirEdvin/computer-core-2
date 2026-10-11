-- Default-deny Phobos validation and native emission. No AST is executed.
local Analyze=require('__computer_core_2__.scripts.native.compiler').analyze
local Limits=require('__computer_core_2__.scripts.guest.limits')
local M={VERSION=1,API=1,source_bytes=16384,nodes=1024,statements=256,depth=16,emitted_bytes=65536}
local binary={['+']=true,['-']=true,['*']=true,['/']=true,['%']=true,['^']=true,
  ['==']=true,['~=']=true,['<']=true,['>']=true,['<=']=true,['>=']=true,['and']=true,['or']=true}
local api={print=true,['math.floor']=true,['math.abs']=true,['math.min']=true,['math.max']=true,
  ['circuit.read']=true,['circuit.write']=true,['circuit.clear']=true}
function M.work()
  -- Identical warm/cold reservation, including parsing, validation, emission,
  -- native text compilation and cache installation. Not a second allowance.
  return {compiler=Limits.compiler_work_per_computer,string=4*M.source_bytes+2*M.emitted_bytes,table=262144,execution=1}
end
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end

local function effect() return {circuits=0,prints=0} end
local function add(a,b) a.circuits=a.circuits+b.circuits; a.prints=a.prints+b.prints end
local function global(node)
  if node.node_type=='index' and node.src_ex_did_not_exist and node.ex.node_type=='upval_ref'
    and node.ex.name=='_ENV' and node.suffix.node_type=='string' and node.suffix.src_is_ident then return node.suffix.value end
end
function M.compile(source,path,repl)
  if type(source)~='string' or #source>M.source_bytes then return nil,(path or '=program')..':1:1: source exceeds 16 KiB' end
  if repl and #source>8192 then return nil,(path or '=lua')..':1:1: submission exceeds 8 KiB' end
  -- Both parse attempts share one reserved compiler allowance.
  -- The prefix is parser input only, never executable player text.
  local remaining=Limits.compiler_work_per_computer
  local function spend(amount)
    if amount>remaining then error('source compiler work limit exceeded',0) end
    remaining=remaining-amount
  end
  local ast,err
  if repl then ast,err=Analyze('return '..source,path,nil,spend) end
  local expression=ast~=nil
  if not ast then ast,err=Analyze(source,path,nil,spend) end
  if not ast then
    if not err:match(':%d+:%d+:') then err=(path or '=program')..':1:1: '..err end
    return nil,err:sub(1,1024)
  end
  local nodes,statements,nesting,locals=0,0,0,0
  local current={}
  local emitted_work=0
  local function reserve(bytes)
    if bytes>2*M.emitted_bytes-emitted_work then error((path or '=program')..':1:1: emission work limit exceeded',0) end
    emitted_work=emitted_work+bytes
  end
  local function cat(parts,separator)
    separator=separator or ''
    local bytes=math.max(0,#parts-1)*#separator
    for _,part in ipairs(parts) do bytes=bytes+#part end
    reserve(bytes)
    return table.concat(parts,separator)
  end
  local function quote(value) reserve(4*#value+2); return string.format('%q',value) end
  local function fail(node,message)
    local line,column=node.line or 1,node.column or 1
    if expression and line==1 then column=math.max(1,column-7) end
    error((path or '=program')..':'..line..':'..column..': '..message,0)
  end
  local function visit(node)
    nodes=nodes+1; if nodes>M.nodes then fail(node,'AST node limit exceeded') end
  end
  local function enter(node)
    visit(node); nesting=nesting+1; if nesting>M.depth then fail(node,'nesting limit exceeded') end
  end
  local expr,block
  local function field(node,parameter)
    return node.node_type=='index' and node.dot_token and node.suffix.node_type=='string'
      and node.suffix.src_is_ident and #node.suffix.value<=64
      and (type(parameter)=='string' and global(node.ex)==parameter
        or node.ex.node_type=='local_ref' and node.ex.reference_def==parameter) and node.suffix.value
  end
  local function target(node,declare)
    visit(node)
    if node.node_type=='local_ref' and node.reference_def~=current.event and node.reference_def~=current.state then
      local def=node.reference_def
      if declare then
        locals=locals+1; reserve(32); current.names[def]='v'..locals
      end
      if current.names[def] then return current.names[def] end
    end
    local key=field(node,current.state)
    if key and not declare then visit(node.ex); visit(node.suffix); return cat({'s[',quote(key),']'}) end
    fail(node,'assignment requires a declared scalar local or state.FIELD')
  end
  expr=function(node)
    enter(node)
    local result,work=nil,effect()
    local kind=node.node_type
    if kind=='nil' then result='nil'
    elseif kind=='boolean' then result=tostring(node.value)
    elseif kind=='number' then
      if not finite(node.value) then fail(node,'number must be finite') end
      reserve(32); result=string.format('%.17g',node.value)
    elseif kind=='string' then
      if #node.value>256 then fail(node,'scalar string exceeds 256 bytes') end
      result=quote(node.value)
    elseif kind=='local_ref' and current.names[node.reference_def] then result=current.names[node.reference_def]
    elseif kind=='index' then
      local key=field(node,current.state)
      if key then result=cat({'s[',quote(key),']'})
      else
        key=field(node,current.event)
        if key=='tick' or key=='name' then result=cat({'e[',quote(key),']'}) end
      end
      if not result then fail(node,'only literal state.FIELD and event.tick/event.name reads are allowed') end
      visit(node.ex); visit(node.suffix)
    elseif kind=='binop' and binary[node.op] then
      local left,lw=expr(node.left); local right,rw=expr(node.right); add(work,lw); add(work,rw)
      result=cat({'a.scalar((',left,') ',node.op,' (',right,'))'})
    elseif kind=='unop' and (node.op=='-' or node.op=='not' or node.op=='#') then
      local value,w=expr(node.ex); add(work,w); result=cat({'a.scalar(',node.op,' (',value,'))'})
    elseif kind=='concat' then
      local values={}
      for i,value in ipairs(node.exp_list) do local code,w=expr(value); values[i]=code; add(work,w) end
      result=cat({'a.concat(',cat(values,','),')'})
    elseif kind=='call' and not node.is_selfcall then
      visit(node.ex)
      local name=global(node.ex)
      if name then visit(node.ex.ex); visit(node.ex.suffix) end
      if not name and node.ex.node_type=='index' and node.ex.dot_token and node.ex.suffix.src_is_ident then
        local root=global(node.ex.ex)
        if root then
          name=root..'.'..node.ex.suffix.value
          visit(node.ex.ex); visit(node.ex.suffix); visit(node.ex.ex.ex); visit(node.ex.ex.suffix)
        end
      end
      if not api[name] then fail(node,'call is not a direct allowlisted API') end
      if #node.args>64 then fail(node,'call argument limit exceeded') end
      local args={}
      for i,value in ipairs(node.args) do local code,w=expr(value); args[i]=code; add(work,w) end
      if name=='print' then work.prints=work.prints+1
      elseif name:sub(1,8)=='circuit.' then work.circuits=work.circuits+1 end
      result=cat({'a.call(',quote(name),#args>0 and ',' or '',cat(args,','),')'})
    else fail(node,'unsupported restricted expression '..kind) end
    nesting=nesting-1
    return result,work
  end
  block=function(scope)
    enter(scope)
    local chunks,work={},effect()
    local stat=scope.body.first
    while stat do
      visit(stat); statements=statements+1; if statements>M.statements then fail(stat,'statement limit exceeded') end
      local kind=stat.node_type
      if kind=='empty' then
        -- Phobos preserves semicolons as explicit no-op statements.
      elseif kind=='localstat' or kind=='assignment' then
        local lhs,rhs={},{}
        for i,node in ipairs(stat.lhs) do lhs[i]=target(node,kind=='localstat') end
        for i,node in ipairs(stat.rhs or {}) do local code,w=expr(node); rhs[i]=code; add(work,w) end
        chunks[#chunks+1]=cat({kind=='localstat' and 'local ' or '',cat(lhs,','),'=',#rhs>0 and cat(rhs,',') or 'nil',';'})
      elseif kind=='call' then
        local code,w=expr(stat); chunks[#chunks+1]=cat({code,';'}); add(work,w)
      elseif kind=='retstat' then
        if #stat.exp_list>1 then fail(stat,'return accepts at most one scalar') end
        local code=''
        if stat.exp_list[1] then local w; code,w=expr(stat.exp_list[1]); add(work,w) end
        local value=stat.exp_list[1]
        local call=value and value.node_type=='call' and value.ex
        local root=call and call.node_type=='index' and global(call.ex)
        local void=expression and call and (global(call)=='print' or root=='circuit'
          and call.suffix.node_type=='string' and (call.suffix.value=='write' or call.suffix.value=='clear'))
        if void then chunks[#chunks+1]=cat({'do ',code,'; return nil,false end;'})
        else chunks[#chunks+1]=cat({'do return ',code~='' and code or 'nil',repl and ',true' or '', ' end;'}) end
      elseif kind=='dostat' then
        local code,w=block(stat); chunks[#chunks+1]=cat({'do ',code,' end;'}); add(work,w)
      elseif kind=='ifstat' then
        local worst=effect()
        for i,branch in ipairs(stat.ifs) do
          local condition,cw=expr(branch.condition); add(work,cw)
          local body,bw=block(branch)
          worst.circuits=math.max(worst.circuits,bw.circuits); worst.prints=math.max(worst.prints,bw.prints)
          chunks[#chunks+1]=cat({i==1 and 'if ' or 'elseif ',condition,' then ',body})
        end
        if stat.elseblock then
          local body,bw=block(stat.elseblock)
          worst.circuits=math.max(worst.circuits,bw.circuits); worst.prints=math.max(worst.prints,bw.prints)
          chunks[#chunks+1]=cat({'else ',body})
        end
        chunks[#chunks+1]='end;'; add(work,worst)
      else fail(stat,'unsupported restricted statement '..kind) end
      stat=stat.next
    end
    nesting=nesting-1
    return cat(chunks,'\n'),work
  end
  local ok,result=pcall(function()
    local generated,maxcircuits,maxprints
    if repl then
      current={state='state',event='event',names={}}
      local code,w=block(ast)
      if w.circuits>16 or w.prints>8 then fail(ast,'submission exceeds 16 circuit / 8 print calls') end
      maxcircuits,maxprints=w.circuits,w.prints
      generated=cat({'return {interval=1,on_start=function(a,e,s)\n',code,'\nend}'})
    else
    local ret=ast.body.first
    while ret and ret.node_type=='empty' do visit(ret); ret=ret.next end
    local following=ret and ret.next
    while following and following.node_type=='empty' do visit(following); following=following.next end
    if not ret or ret.node_type~='retstat' or following or #ret.exp_list~=1 then fail(ret or ast,'expected exactly return { interval=..., on_start=..., on_tick=... }') end
    visit(ast); visit(ret)
    local descriptor=ret.exp_list[1]; visit(descriptor)
    if descriptor.node_type~='constructor' then fail(descriptor,'program descriptor must be a literal table') end
    local seen,handlers,interval={}, {},60
    maxcircuits,maxprints=0,0
    for _,entry in ipairs(descriptor.fields) do
      if entry.type=='list' or entry.key.node_type~='string' or not entry.key.src_is_ident then fail(descriptor,'descriptor fields must be literal named entries') end
      visit(entry.key); visit(entry.value)
      local name,value=entry.key.value,entry.value
      if seen[name] then fail(value,'duplicate descriptor field '..name) end
      seen[name]=true
      if name=='interval' then
        if value.node_type~='number' or not finite(value.value) or value.value~=math.floor(value.value) or value.value<1 or value.value>3600 then fail(value,'interval must be a literal integer in 1..3600') end
        interval=value.value
      elseif name=='on_start' or name=='on_tick' then
        if value.node_type~='func_proto' then fail(value,'handler must be a function literal') end
        local fn=value.func_def
        if fn.is_vararg or #fn.params~=2 or fn.params[1].name~='event' or fn.params[2].name~='state' then fail(fn,'handler parameters must be (event, state)') end
        visit(fn.params[1]); visit(fn.params[2])
        current={event=fn.params[1].reference_def,state=fn.params[2].reference_def,names={}}
        local code,w=block(fn)
        if w.circuits>16 or w.prints>8 then fail(fn,'callback exceeds 16 circuit / 8 print calls') end
        maxcircuits=math.max(maxcircuits,w.circuits); maxprints=math.max(maxprints,w.prints)
        handlers[#handlers+1]=cat({name,'=function(a,e,s)\n',code,'\nend'})
      else fail(value,'unknown descriptor field '..name) end
    end
    if #handlers==0 then fail(descriptor,'at least one handler is required') end
    generated=cat({'return {interval=',tostring(interval),',',cat(handlers,','),'}'})
    end
    if #generated>M.emitted_bytes then fail(ast,'emitted wrapper exceeds 64 KiB') end
    -- Only this freshly emitted text enters load; neither source nor storage
    -- supplies generated code. No globals exist in the wrapper environment.
    local loader,loaderr=load(generated,'=restricted:'..(path or 'program'),'t',{})
    if not loader then fail(ast,tostring(loaderr):sub(1,512)) end
    local compiled=loader()
    local reconstruction=M.work()
    compiled.work={compiler=reconstruction.compiler,execution=129+2*nodes+2*statements+16*maxcircuits+8*maxprints,
      string=reconstruction.string+32768+256*nodes,table=reconstruction.table+8192+16*nodes,event=4096,filesystem=4096}
    for domain,amount in pairs(compiled.work) do
      local cap=({compiler=Limits.compiler_work_per_computer,execution=Limits.instructions_per_computer,string=Limits.string_work_per_computer,
        table=Limits.table_work_per_computer,event=Limits.event_work_per_computer,filesystem=Limits.filesystem_work_per_computer})[domain]
      if amount>cap then fail(ast,'complete callback exceeds fresh '..domain..' quota') end
    end
    compiled.nodes,compiled.statements=nodes,statements
    return compiled
  end)
  if not ok then return nil,tostring(result):sub(1,1024) end
  return result
end
return M
