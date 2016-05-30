let s:save_cpo = &cpo
set cpo&vim

let s:exclude_task_pattern = get(g:, 'unite_source_gulp_exclude_task_pattern', '^_')
let s:run_task_cmd = get(g:, 'unite_source_gulp_run_task_cmd', 'Start -wait=always gulp --cwd %s %s')
let s:cache = []

function! unite#sources#gulp#define() abort
    return s:source
endfunction

let s:source = {
    \ 'name': 'gulp',
    \ 'description': 'candidates from gulp tasks',
    \ 'default_action': { 'common': 'execute' },
    \ 'sorters': 'sorter_word',
    \ 'matchers': 'matcher_fuzzy',
    \ 'action_table': {},
    \ 'hooks': {},
    \ }

function! s:source.hooks.on_init(args, context) abort
    let a:context.source__name = 'gulp'
    let a:context.cwd = expand('%:p:h')
endfunction

function! s:source.gather_candidates(args, context) abort

  if !has('nvim') && !(has('job') && has('channel'))
      let a:context.is_async = 0
      call s:show_error('unite-gulp: +job control or neovim is required')
      return []
  endif

  let use_cache = !empty(s:cache) && (empty(a:args) || a:args[0] != 'refresh')

  if use_cache
      let a:context.is_async = 0
      return s:cache
  endif

  call unite#clear_message()
  call unite#print_message('[gulp] Looking for tasks...')

  let get_tasks_cmd = 'gulp --tasks-simple --cwd ' . a:context.cwd
  call s:job_start(a:context, get_tasks_cmd)

  return []

endfunction

function! s:source.async_gather_candidates(args, context) abort

    let job_info = s:job_info.get(a:context.source__job_id)
    let job_info.eof = s:job_status(job_info) !=# 'run'
    if !job_info.eof | return [] | endif

    let a:context.is_async = 0
    call unite#clear_message()

    let exitval = s:job_exitval(job_info)

    if exitval != 0
        let s:cache = []
        let error = empty(job_info.candidates) ? 'No gulpfile found' : 'Error: ' . join(job_info.candidates)
        return [{ 'word': substitute(error, '^\[[0-9:]\+\]', '', ''), 'source': 'gulp' }]
    endif

    let candidates = filter(copy(job_info.candidates), 'v:val !~ "' . s:exclude_task_pattern . '"')
    let s:cache = map(candidates, "{
                \ 'word': v:val,
                \ 'source': 'gulp',
                \ 'kind': 'common',
                \ 'cwd': a:context.cwd
                \ }")

    return s:cache

endfunction

"{{{ job control

let s:job_info = {}

function! s:job_info.get(id) abort
    if !has_key(self, a:id)
        let self[a:id] = { 'job_ref': 0, 'candidates': [], 'eof': 0, 'status': 'run', 'exitval': 0 }
    endif
    return self[a:id]
endfunction

function! s:job_start(context, cmd) abort

   if !has('nvim')
       let cwd = getcwd()
       if unite#util#is_windows() && cwd =~ '^\\\\'
           execute 'lcd ' . $WINDIR
       endif
       let job = job_start([&shell, &shellcmdflag, a:cmd], { 'callback': function('s:job_handler_vim') })
       execute 'lcd ' . cwd
       let job_id = s:id(job_getchannel(job))
       let job_info = s:job_info.get(job_id)
       let job_info.job_ref = job
   else
       let Handler = function('s:job_handler_nvim')
       let job_id = jobstart(a:cmd, { 'on_stdout': Handler, 'on_stderr': Handler, 'on_exit': Handler })
   endif

   let a:context.source__job_id = job_id

endfunction

function! s:job_handler(id, payload, event) abort

    let job_info = s:job_info.get(a:id)

    if a:event ==# 'exit'
        let job_info.status = 'exit'
        let job_info.exitval = a:payload
        return
    endif

    call extend(job_info.candidates, s:lines(a:payload))

endfunction

function! s:lines(payload)
    return has('nvim')
            \ ? map(a:payload, "iconv(v:val, 'char', &encoding)")
            \ : split(iconv(a:payload, 'char', &encoding), "\n")
endfunction

function! s:id(channel) abort
    return matchstr(a:channel, '\d\+')
endfunction

function! s:job_handler_vim(ch, msg) abort
    call s:job_handler(s:id(a:ch), a:msg, '')
endfunction

function! s:job_handler_nvim(id, msg, event) abort
    call s:job_handler(a:id, a:msg, a:event)
endfunction

function! s:job_status(job_info)
    return !has('nvim') ? job_status(a:job_info.job_ref) : a:job_info.status
endfunction

function! s:job_exitval(job_info)
    return !has('nvim') ? job_info(a:job_info.job_ref).exitval : a:job_info.exitval
endfunction
"}}}

" action table {{{

let s:source.action_table.execute = { 'description': 'Run' }
let s:last_task_cmd = ''

function! s:source.action_table.execute.func(candidate) abort
    if !has_key(a:candidate, 'cwd') | return | endif
    let s:last_task_cmd = printf(s:run_task_cmd, a:candidate.cwd, a:candidate.word)
    execute s:last_task_cmd
endfunction

"}}}

" repeat last task {{{

function! unite#sources#gulp#repeat() abort
    if empty(s:last_task_cmd)
        call s:show_error('no task to repeat')
    else
        execute s:last_task_cmd
    endif
endfunction

" }}}

function! s:show_error(msg)
    echohl ErrorMsg | echomsg a:msg | echohl None
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
