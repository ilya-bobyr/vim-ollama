" SPDX-License-Identifier: GPL-3.0-or-later
" SPDX-CopyrightText: 2024 Gerhard Gappmeier <gappy1502@gmx.net>

" This file defines context machinery for the plugin.

" All the context that have been defined so far.
"
" Context name is the key and the value is an object with the following
" properties TODO:
"
" {
"   project_root:
"     "<An absolute path to the directory that will be used as a starting point
"       for all the glob patters in the `files` key.  As Vim can change the
"       current directory and has a notion of a current directory per window, it
"       is necessary to have a stable reference point for the patterns in
"       `files`.>",
"   files: [
"     "<A list of strings that are used to select files.  'globpath()' is used,
"       with the `project_root` value as a reference point .  Each string is
"       matched against the open buffers, and if a buffer matches, then the
"       buffer content is provided to the model.  File system is checked for
"       matches as well, and if any files are found, they are added to the
"       context.
"
"       Buffers are added to the context last and in the reverse order of their
"       access time.  In other words, buffers that you looked at last will be
"       last in the context.  Putting them closer to the end of the prompt gives
"       them more weight.
"
"       Files that are not loaded in buffers and added to the context in the
"       order listed.  So put more general files first, and more specific files
"       last.>",
"   ],
"   additional_instructions:
"     "<A string that is added to the prompt just before the user prompt, but
"       after any predefined model prompt.  It is supposed to clarify the intent
"       of this session for the model.>",
"
" TODO I think it makes sense to be able to overwrite most of the global options
" at the session level.  Model selection are the first candidates, but it would
" make sense to go through all the global options and add anything else that
" makes sense.
"
"   completion_model:
"     "<Name of the completion model to be used for this context.  If not set,
"       then the `g:ollama_model` value is used.>",
"   chat_model:
"     "<Name of the chat model to be used for this context.  If not set, then
"       the `g:ollama_chat_model` value is used.>",
"   edit_model:
"     "<Name of the edit model to be used for this context.  If not set, then
"       the `g:ollama_edit_model` value is used.>",
" }
"
" As content of the constructed contexts could be quite valuable, they are
" preserved when session is written via `:mksession`, and are restored when a
" session file is loaded.
"
" All contexts are stored in the `g:ollama_contexts_dir`, and use the session
" file path as a key.
"
" See TODO for details.
let g:ollama_contexts = {}

" TODO This flag should be set to `v:true` every time `g:ollama_contexts` is
" updated.  It would allow the plugin to inform the user if they might be
" performing an operation that would destroy an unsaved context.
let g:ollama_contexts_modified = v:false

" This is a cache, holding files that are part of the corresponding context, in
" case a file is not loaded into a buffer.  Files that are loaded into buffers
" are inserted into context from the buffer directly.
"
" TODO Not implemented yet.  Need to populate this on context change and update
" when a buffer is loaded or unloaded.
let g:ollama_contexts_files = {}

" Context targeted by `ollama#context#SetProjectRoot`, `ollama#context#Add`,
" `ollama#context#Delete`.
let g:ollama_context_current = "default"

" Context that should be used by the completion model.
"
" Defaults to "default" if not set.
let g:ollama_completion_context = v:null

" Context that should be used by the chat model.
"
" Defaults to "default" if not set.
let g:ollama_chat_context = v:null

" Context that should be used by the edit model.
"
" Defaults to "default" if not set.
let g:ollama_edit_context = v:null

" The directory where all the context files are stored.
" TODO It would be good to have this switch automatically between XDG and
" non-XDG modes, based on some environment variables, perhaps?
let g:ollama_contexts_dir = expand("~/.local/share/vim/vim-ollama/contexts")

augroup OllamaContext
  autocmd!
  autocmd SessionLoadPost * call ollama#context#LoadSessionContexts()
  autocmd SessionWritePost * call ollama#context#SaveSessionContexts()
augroup END

command! -nargs=+ OllamaContextNew call ollama#context#New(<f-args>)
command! -nargs=0 OllamaContextList call ollama#context#List()
command! -nargs=1 OllamaContextSetCurrent
      \ call ollama#context#SetCurrent(<f-args>)
command! -nargs=+ OllamaContextUse call ollama#context#Use(<f-args>)
command! -nargs=1 OllamaContextDelete call ollama#context#Delete(<f-args>)
command! -nargs=1 OllamaContextSetProjectRoot
      \ call ollama#context#SetProjectRoot(<f-args>)
command! -nargs=1 OllamaContextAdd call ollama#context#Add(<f-args>)
command! -nargs=1 OllamaContextRemove call ollama#context#Delete(<f-args>)
