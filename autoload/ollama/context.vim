" Handler for the SessionLoadPost event.
"
" TODO For some reason I see this method invoked twice.  Would it make sense to
" filter duplicate invocations?
function! ollama#context#LoadSessionContexts()
  call ollama#logger#Debug("LoadSessionContexts")
  let l:session_id = s:ContextSessionId()
  if l:session_id == ''
    return
  endif

  call ollama#logger#Debug("LoadSessionContexts: " .. l:session_id)

  " If a new session is being loaded, we should probably remove old contexts.
  " But it is not entirely clear to me that this would always be the best
  " choice.
  " Users may not necessary connection the context they setup to a session and
  " can be upset that the context was lost.
  "
  " A better solution would be to consider if the context was modified since it
  " was preserved.  And, even, maybe a setting that controls different
  " behaviors.
  "
  " TODO React to the `g:ollama_contexts_modified` value, and ask the user as to
  " what should be done if load fails, and the existing context had been
  " modified.
  "
  " For now, the most simple solution is to just always preserve current context
  " if load fails.
  "
  " let g:ollama_contexts = {}

  let l:contexts_file = g:ollama_contexts_dir .. "/" .. l:session_id .. ".json"
  if !filereadable(l:contexts_file)
    return
  endif

  let l:contexts_file_content = readfile(l:contexts_file)
  if len(l:contexts_file_content) == 0
    echoerr "WARNING: Failed to restore vim-ollama contexts."
    echoerr "  Contexts file is empty."
    echoerr "  Contexts file: " .. l:contexts_file
    return
  endif

  call ollama#logger#Debug("LoadSessionContexts: contexts_file_content:\n"
        \ .. string(l:contexts_file_content))

  if len(l:contexts_file_content) > 1
    echoerr "WARNING: Failed to restore vim-ollama sessions."
    echoerr "  Contexts file contains more than a single line."
    echoerr "  Contexts file: " .. l:contexts_file
    return
  endif

  let l:contexts = json_decode(l:contexts_file_content[0])
  if type(l:contexts) != v:t_dict
    echoerr "WARNING: Failed to restore vim-ollama sessions."
    echoerr "  Contexts file top level item is not a dictionary, got: "
          \ .. typename(l:contexts)
    echoerr "  Contexts file: " .. l:contexts_file
    return
  endif

  let g:ollama_contexts = l:contexts
  call ollama#logger#Debug("LoadSessionContexts: success:\n"
        \ .. json_encode(g:ollama_contexts))
endfunction

function! ollama#context#SaveSessionContexts()
  let l:session_id = s:ContextSessionId()
  if l:session_id == ''
    return
  endif
  call ollama#logger#Debug("SaveSessionContexts: " .. l:session_id)

  call mkdir(g:ollama_contexts_dir, "p", 0o750)

  let l:contexts_file = g:ollama_contexts_dir .. "/" .. l:session_id .. ".json"
  call ollama#logger#Debug("  Saving into: " .. l:contexts_file)
  call writefile([json_encode(g:ollama_contexts)], l:contexts_file, 's')
endfunction

function! s:ContextSessionId()
  if v:this_session == ''
    return ''
  endif

  let l:id = fnamemodify(v:this_session, ":p:~")

  " A bijective mapping makes sure there are no collisions.
  " /  => #
  " \  => #-
  " ~  => #%
  " #([^-%+=#]) => #+\1
  " #- => #=-
  " #% => #=%
  " #+ => #=+
  " #= => #==
  " ## => #=#
  return substitute(l:id, '\%([/\\~]\|#\(.\)\)',
        \   {m -> m[0] == '/' ? '#'
        \       : m[0] == '\' ? '#-'
        \       : m[0] == '~' ? '#%'
        \       : (m[1] == '-' ? '#=-'
        \        : m[1] == '%' ? '#=%'
        \        : m[1] == '+' ? '#=+'
        \        : m[1] == '='? '#=='
        \        : m[1] == '#'? '#=#'
        \        : '#+' .. m[1]
        \       )},
        \ 'g')
endfunction

" Constructs context for a completion request.
function! ollama#context#ConstructCompletionContext()
  if exists("g:ollama_completion_context")
        \ && g:ollama_completion_context != v:null
    return s:ConstructContext(g:ollama_completion_context)
  endif

  return s:ConstructContext("default")
endfunction

" Constructs context for a review request.
function! ollama#context#ConstructReviewContext()
  if exists("g:ollama_review_context")
        \ && g:ollama_review_context != v:null
    return s:ConstructContext(g:ollama_review_context)
  endif

  return s:ConstructContext("default")
endfunction

" Constructs context for an edit request.
function! ollama#context#ConstructEditContext()
  if exists("g:ollama_edit_context")
        \ && g:ollama_edit_context != v:null
    return s:ConstructContext(g:ollama_edit_context)
  endif

  return s:ConstructContext("default")
endfunction

" Constructs context for the given context ID.
function! s:ConstructContext(context_id)
  if !exists("g:ollama_contexts")
    return ''
  endif

  call ollama#logger#Debug("s:ConstructContext(" .. a:context_id .. ")")

  let l:context = get(g:ollama_contexts, a:context_id, v:null)
  if type(l:context) == v:t_none
    return ''
  endif

  if type(l:context) != v:t_dict
    echoerr "ERROR: Context in g:ollama_contexts is not a dictionary."
    echoerr "  Got: " .. typename(l:context)
    echoerr "  Value: " .. string(l:context)
    return ''
  endif
  call ollama#logger#Debug("  context:\n" .. json_encode(l:context))

  let l:project_root = l:context.project_root
  let l:files = l:context.files
  let l:additional_instructions = get(l:context, "additional_instructions", '')

  " Make project root absolute, to simplify comparisons.
  let l:project_root = fnamemodify(l:project_root, ':p')
  " It should not end with a forward slash, as `ollama#context#New()` guarantees
  " that, but just in case.
  let l:project_root = substitute(l:project_root, '/\+$', '', '')

  let l:res = ''

  " TODO This is quite inefficient.  Similarly to how I want to cache files in
  " `g:ollama_contexts_files` I should probably cache match results for the
  " `files` selector for buffers.  There is no need to copy the buffer contents,
  " but it makes sense to keep an up-to-date list of buffers that match.
  "
  " I would than need to only go through the `files` when a buffer is created or
  " deleted.
  let l:buffers = getbufinfo({'buflisted': 1})
  " We want the most recently visited buffers to be closer to the completion
  " prompt.
  call sort(l:buffers, {a, b -> a.lastused - b.lastused})

  let l:regpats = s:GlobsToAbsRegpats(l:project_root, l:files)

  for l:buffer in l:buffers
    " If the buffer is not loaded is has no data.
    if !l:buffer.loaded
      continue
    endif

    let l:bufnr = l:buffer.bufnr
    let l:buffer_path = fnamemodify(bufname(l:bufnr), ':p')
    if s:PathMatchesRegpats(l:buffer_path, l:regpats)
      " For the context we should either use path relative to the project root,
      " or an absolute path.  It does not make sense to provide paths relative
      " to the current working directory.
      let l:context_path = s:RemoveAbsPathPrefix(l:project_root, l:buffer_path)

      let l:res ..= "<file path=\"" .. l:context_path .. "\">\n"
      for l:line in getbufline(l:bufnr, 1, '$')
        let l:res ..= l:line .. "\n"
      endfor
      let l:res ..= "</file>\n"
    endif
  endfor

  if l:additional_instructions != ''
    if l:res != ''
      let l:res ..= "\n"
    endif
    let l:res ..=
          \ "<instructions>" .. l:additional_instructions .. "</instructions>\n"
  endif

  call ollama#logger#Debug("  prompt:\n" .. l:res)

  return l:res
endfunction

" Removes the 'root' prefix from 'path', or returns 'path' as is, if 'root' is
" not a prefix of 'path'.  'root' must not end with a forward slash, and only
" patches if the next character after the match is a forward slash.  With 'root'
" of "/a/b", 'path' of "/a/b/c" produces "c", but 'path' of "/a/bc/d" is
" preserved as is.
function s:RemoveAbsPathPrefix(root, path)
  let l:end = len(a:root)
  if a:path[0:l:end - 1] ==# a:root && a:path[l:end] ==# "/"
    return a:path[l:end + 1:]
  else
    return a:path
  endif
endfunction

" Converts a list of file globs into regular expressions, using `glob2regpat()`.
" For patterns that start with "~/" prefixes them with the user home path.
" For patterns that are not absolute paths, prefixes them with "a:root".
function! s:GlobsToAbsRegpats(root, globs)
  let l:res = []

  for l:pattern in a:globs
    " We are going to match against the absolute path, so we to expand "~/"
    " explicitly.  At the same time, we do not want to call "expand()" for the
    " whole pattern.
    if l:pattern =~# '\_^\~/'
      let l:pattern = expand("~/") .. l:pattern[2:]
    elseif l:pattern !~# '\_^/'
      let l:pattern = a:root .. "/" .. l:pattern
    endif

    call add(l:res, glob2regpat(l:pattern))
  endfor

  return l:res
endfunction

function! s:PathMatchesRegpats(path, regpats)
  for l:regpat in a:regpats
    " Use glob() to check if the file matches the pattern
    " glob() returns a list, so we check if our file is in that list
    if match(a:path, l:regpat) != -1
      return 1
    endif
  endfor

  return 0
endfunction

" === Command handling functions ===

function! ollama#context#New(name, ...)
  if has_key(g:ollama_contexts, a:name)
    echoerr "ERROR: Context with this name already exists: " .. a:name
    return
  endif

  if a:0 > 1
    echoerr "Too many arguments."
          \ "OllamaContextNew may take a single optional that defines"
          \ "the new context root."
    return
  endif

  if a:0 == 1
    let l:project_root = a:1
  else
    " Use current window directory as the starting suggestion.
    let l:project_root = getcwd()
    while v:true
      let l:project_root = input("Directory to use as the project root: ",
            \ l:project_root, 'dir')
      echon "\n"
      if l:project_root == ''
        echomsg "Cancelled context creation"
        return
        break
      endif

      if isdirectory(l:project_root)
        break
      endif

      " Check if l:project_root points to an existing directory
      let l:retry = v:false
      echomsg "Selected path does not point to an existing directory"
      while v:true
        let l:ans = input("Are you sure you want to use it? (y/n)")
        echon "\n"
        if l:ans ==? 'y'
          break
        endif
        if l:ans ==? 'n'
          let l:retry = v:true
          break
        endif
      endwhile

      if !l:retry
        break
      endif
    endwhile
  endif

  " And make it relative, if possible.
  let l:project_root = fnamemodify(l:project_root, ':p:~')
  " Clean up any trailing forward slashes.
  let l:project_root = substitute(l:project_root, '/\+$', '', '')

  let g:ollama_contexts[a:name] = {
        \ 'project_root': l:project_root,
        \ 'files': [],
        \ }
  let g:ollama_context_current = a:name
  echomsg "Created a new LLM context, and set it as current: " .. a:name
endfunction

function! ollama#context#List()
  echoerr "Not implemented yet"
endfunction
