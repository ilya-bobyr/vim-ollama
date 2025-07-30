function! ollama#context#LoadSessionContexts()
  let l:session_id = s:ContextSessionId()
  if l:session_id == ''
    return
  endif

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

  let l:contexts_file = g:ollama_contexts_dir .. l:session_id .. ".json"
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
          \ . typename(l:contexts)
    echoerr "  Contexts file: " .. l:contexts_file
    return
  endif

  let g:ollama_contexts = l:contexts
endfunction

function! ollama#context#SaveSessionContexts()
  let l:session_id = s:ContextSessionId()
  if l:session_id == ''
    return
  endif

  call mkdir(g:ollama_contexts_dir, "p", 0o750)

  let l:contexts_file = g:ollama_contexts_dir .. l:session_id .. ".json"
  call writefile(json_encode([g:ollama_contexts]), l:contexts_file, 's')
endfunction

function! s:ContextSessionId()
  if v:this_session == ''
    return ''
  endif

  " A bijective mapping makes sure there are no collisions.
  " /  => #
  " \  => #-
  " #([^-+=#]) => #+\1
  " #- => #=-
  " #+ => #=+
  " #= => #==
  " ## => #=#
  let l:session_id =
        \ substitute(v:this_session, '\%([/\\]\|#\(.\)\)',
        \   {m -> m[0] == '/' ? '#'
        \       : m[0] == '\' ? '#-'
        \       : (m[1] == '-' ? '#=-'
        \        : m[1] == '+' ? '#=+'
        \        : m[1] == '='? '#=='
        \        : m[1] == '#'? '#=#'
        \        : '#+' .. m[1]
        \       )},
        \ 'g')
  return l:session_id
endfunction
