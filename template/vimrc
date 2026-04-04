set fileencoding=utf-8
set termencoding=utf-8
set encoding=utf-8

set tabstop=4
set shiftwidth=4
set number
set ruler
set autoindent
set hlsearch
set incsearch
set showcmd
set nocompatible
set laststatus=2
set backspace=indent,eol,start

filetype plugin on
syntax on

" inoremap ' ''<Esc>i
" inoremap " ""<Esc>i
if has("autocmd")
	au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
endif