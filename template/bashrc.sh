# Ported from template/config.fish — keep in sync when changing shell setup.
# Non-interactive shells: skip aliases and prompt-related noise.
[[ $- != *i* ]] && return

# Add paths only if they are not already in PATH
add_to_path() {
  local dir
  for dir in "$@"; do
    case ":${PATH}:" in
      *":${dir}:"*) ;;
      *) PATH="${dir}:${PATH}" ;;
    esac
  done
  export PATH
}

add_to_path_config() {
  local d
  for d in "$@"; do
    PATH="${d}:${PATH}"
  done
  export PATH
  {
    printf 'add_to_path'
    for d in "$@"; do printf ' %q' "$d"; done
    printf '\n'
  } >> "${HOME}/.bashrc"
}

add_pwd_to_path_config() {
  local p
  p=$(pwd)
  PATH="${p}:${PATH}"
  export PATH
  printf 'add_to_path %q\n' "$p" >> "${HOME}/.bashrc"
}

export LANG=en_US.UTF-8

proxy_port=7890
proxy_ip=127.0.0.1

proxy_on() {
  local var url="http://${proxy_ip}:${proxy_port}"
  for var in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY; do
    local cmd="export ${var}=${url}"
    echo "$cmd"
    eval "$cmd"
  done
  export no_proxy=127.0.0.1,localhost
  export NO_PROXY=127.0.0.1,localhost
  echo -e "\033[32m[√] Proxy enabled\033[0m"
}

proxy_off() {
  local var
  for var in http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY no_proxy; do
    local cmd="unset ${var}"
    echo "$cmd"
    eval "$cmd"
  done
  echo -e "\033[31m[×] Proxy disabled\033[0m"
}

cuda() {
  local devs="$1"
  shift
  echo "CUDA_VISIBLE_DEVICES=${devs} $*"
  env CUDA_VISIBLE_DEVICES="${devs}" "$@"
}

hfmon() {
  export HF_ENDPOINT="https://hf-mirror.com"
}

hfmoff() {
  unset HF_ENDPOINT
}

ca_off() {
  export __CURL_CA_BUNDLE_BACKUP="${CURL_CA_BUNDLE-}"
  export __REQUESTS_CA_BUNDLE_BACKUP="${REQUESTS_CA_BUNDLE-}"
  export CURL_CA_BUNDLE=""
  export REQUESTS_CA_BUNDLE=""
  echo "CA bundle environment variables disabled and backed up."
}

ca_on() {
  if [[ -n "${__CURL_CA_BUNDLE_BACKUP+x}" ]]; then
    export CURL_CA_BUNDLE="${__CURL_CA_BUNDLE_BACKUP}"
  else
    unset CURL_CA_BUNDLE
  fi

  if [[ -n "${__REQUESTS_CA_BUNDLE_BACKUP+x}" ]]; then
    export REQUESTS_CA_BUNDLE="${__REQUESTS_CA_BUNDLE_BACKUP}"
  else
    unset REQUESTS_CA_BUNDLE
  fi

  echo "CA bundle environment variables restored."
  echo "CURL_CA_BUNDLE=${CURL_CA_BUNDLE-}"
  echo "REQUESTS_CA_BUNDLE=${REQUESTS_CA_BUNDLE-}"
}

start_if_not_running() {
  local process_name="$1"
  shift
  if ! pgrep -f "$process_name" >/dev/null; then
    echo "Starting ${process_name}..."
    eval "$@" &
    sleep 2
    echo "${process_name} has been started successfully"
  else
    echo "${process_name} is already running"
  fi
}

: "${CUDA_DIRS:=${HOME}/shared_software/cuda:${HOME}/software/cuda}"
export CUDA_DIRS
__CUDA_TAB=$'\t'

__cuda_realpath() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p" 2>/dev/null || echo "$p"
  else
    echo "$p"
  fi
}

__cuda_version_for_root() {
  local root="$1"
  local ver base
  [[ -x "${root}/bin/nvcc" ]] || return 1
  ver=$("${root}/bin/nvcc" -V 2>&1 | sed -n 's/.*release \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)
  if [[ -n "${ver}" ]]; then
    echo "${ver}"
    return 0
  fi
  base=$(basename "${root}")
  ver=$(echo "${base}" | sed -n 's/^cuda-\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
  if [[ -n "${ver}" ]]; then
    echo "${ver}"
    return 0
  fi
  return 1
}

__cuda_collect_candidates() {
  local d base _tmp
  _tmp="${CUDA_DIRS}:"
  while [[ -n "${_tmp}" ]]; do
    base="${_tmp%%:*}"
    _tmp="${_tmp#*:}"
    [[ -z "${base}" ]] && continue
    if [[ -d "${base}" ]]; then
      while IFS= read -r d; do
        [[ -n "${d}" ]] && printf '%s\n' "${d}"
      done < <(command find "${base}" -maxdepth 1 -mindepth 1 -type d -name 'cuda-*' 2>/dev/null)
    fi
  done
  for d in /usr/local/cuda /opt/cuda /opt/homebrew/opt/cuda /usr/local/opt/cuda; do
    [[ -d "${d}" ]] && printf '%s\n' "${d}"
  done
  while IFS= read -r d; do
    [[ -n "${d}" ]] && printf '%s\n' "${d}"
  done < <(command find /usr/local -maxdepth 1 -mindepth 1 -type d -name 'cuda-*' 2>/dev/null)
}

__cuda_enumerate_valid_roots() {
  local raw rp s seen
  local -a seen_real roots_out
  while IFS= read -r raw; do
    [[ -z "${raw}" ]] && continue
    [[ -x "${raw}/bin/nvcc" ]] || continue
    rp=$(__cuda_realpath "${raw}")
    seen=0
    for s in "${seen_real[@]}"; do
      if [[ "${s}" == "${rp}" ]]; then
        seen=1
        break
      fi
    done
    [[ "${seen}" -eq 1 ]] && continue
    seen_real+=("${rp}")
    roots_out+=("${raw}")
  done < <(__cuda_collect_candidates)
  printf '%s\n' "${roots_out[@]}"
}

__cuda_discover() {
  local tab="${__CUDA_TAB}"
  local raw rp ver pair dup dupv s v pa
  local -a pairs seen_real seen_v filtered
  while IFS= read -r raw; do
    [[ -z "${raw}" ]] && continue
    [[ -x "${raw}/bin/nvcc" ]] || continue
    rp=$(__cuda_realpath "${raw}")
    dup=0
    for s in "${seen_real[@]}"; do
      if [[ "${s}" == "${rp}" ]]; then
        dup=1
        break
      fi
    done
    [[ "${dup}" -eq 1 ]] && continue
    seen_real+=("${rp}")
    ver=$(__cuda_version_for_root "${raw}") || continue
    pairs+=("${ver}${tab}${raw}")
  done < <(__cuda_collect_candidates)

  filtered=()
  for pair in "${pairs[@]}"; do
    ver="${pair%%"${tab}"*}"
    pa="${pair#*"${tab}"}"
    dupv=0
    for v in "${seen_v[@]}"; do
      if [[ "${v}" == "${ver}" ]]; then
        dupv=1
        break
      fi
    done
    [[ "${dupv}" -eq 1 ]] && continue
    seen_v+=("${ver}")
    filtered+=("${ver}${tab}${pa}")
  done
  if ((${#filtered[@]} > 0)); then
    printf '%s\n' "${filtered[@]}" | sort -t "${tab}" -k1,1V
  fi
}

__cuda_normalize_version_arg() {
  local want="$1"
  if [[ "${want}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "${want}"
    return
  fi
  if [[ "${want}" =~ ^[0-9]{3}$ ]]; then
    echo "${want:0:2}.${want:2:1}"
    return
  fi
  echo "${want}"
}

__cuda_join_colon_array() {
  local out="" e
  for e in "$@"; do
    out="${out:+$out:}${e}"
  done
  printf '%s' "${out}"
}

__cuda_strip_cuda_paths() {
  local entry _tmp r drop
  local -a roots newp newld
  roots=()
  while IFS= read -r r; do
    [[ -n "${r}" ]] && roots+=("${r}")
  done < <(__cuda_enumerate_valid_roots)

  newp=()
  _tmp="${PATH}:"
  while [[ -n "${_tmp}" ]]; do
    entry="${_tmp%%:*}"
    _tmp="${_tmp#*:}"
    [[ -z "${entry}" ]] && continue
    drop=0
    for r in "${roots[@]}"; do
      if [[ "${entry}" == "${r}/bin" ]]; then
        drop=1
        break
      fi
    done
    [[ "${drop}" -eq 0 ]] && newp+=("${entry}")
  done
  PATH=$(__cuda_join_colon_array "${newp[@]}")
  export PATH

  if [[ -n "${LD_LIBRARY_PATH+x}" ]]; then
    newld=()
    _tmp="${LD_LIBRARY_PATH}:"
    while [[ -n "${_tmp}" ]]; do
      entry="${_tmp%%:*}"
      _tmp="${_tmp#*:}"
      [[ -z "${entry}" ]] && continue
      drop=0
      for r in "${roots[@]}"; do
        if [[ "${entry}" == "${r}/lib64" ]]; then
          drop=1
          break
        fi
      done
      [[ "${drop}" -eq 0 ]] && newld+=("${entry}")
    done
    LD_LIBRARY_PATH=$(__cuda_join_colon_array "${newld[@]}")
    export LD_LIBRARY_PATH
  fi
}

__cuda_apply() {
  local root="$1"
  __cuda_strip_cuda_paths
  export CUDA_HOME="${root}"
  export CUDA_PATH="${root}"
  if [[ -d "${root}/lib64" ]]; then
    LD_LIBRARY_PATH="${root}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export LD_LIBRARY_PATH
  fi
  PATH="${root}/bin${PATH:+:${PATH}}"
  export PATH
}

use_cuda() {
  local version_to_use="$1"
  local line ver pa want f
  local -a avail names
  if [[ -z "${version_to_use}" ]]; then
    echo "Available CUDA installations:"
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      ver="${line%%"${__CUDA_TAB}"*}"
      pa="${line#*"${__CUDA_TAB}"}"
      echo "  ${ver}  ->  ${pa}"
    done < <(__cuda_discover)
    echo "Usage: use_cuda <version>   (e.g. 12.4 or 124)"
    return 0
  fi
  want=$(__cuda_normalize_version_arg "${version_to_use}")
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    ver="${line%%"${__CUDA_TAB}"*}"
    pa="${line#*"${__CUDA_TAB}"}"
    if [[ "${ver}" == "${want}" ]]; then
      __cuda_apply "${pa}"
      echo "Switched to CUDA ${ver}"
      echo "CUDA_HOME = ${CUDA_HOME}"
      return 0
    fi
  done < <(__cuda_discover)
  echo "Unknown or unsupported CUDA version: ${version_to_use}"
  avail=()
  names=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] && avail+=("${line}")
  done < <(__cuda_discover)
  if ((${#avail[@]} == 0)); then
    echo "No CUDA installations found (expected bin/nvcc under scanned roots)."
  else
    names=()
    for line in "${avail[@]}"; do
      f="${line%%"${__CUDA_TAB}"*}"
      names+=("${f}")
    done
    echo -n "Available versions: "
    (IFS=', '; echo "${names[*]}")
  fi
  return 1
}

__cuda_lines=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && __cuda_lines+=("${line}")
done < <(__cuda_discover)

if ((${#__cuda_lines[@]} > 0)); then
  last_idx=$((${#__cuda_lines[@]} - 1))
  __cuda_last="${__cuda_lines[${last_idx}]}"
  __cuda_pa="${__cuda_last#*"${__CUDA_TAB}"}"
  __cuda_apply "${__cuda_pa}"
else
  echo "CUDA: no installation found (scanned CUDA_DIRS and common system paths)." >&2
fi
unset __cuda_lines __cuda_last __cuda_pa last_idx line

alias g++='g++ -finput-charset=UTF-8 -fexec-charset=UTF-8'
alias c++='c++ -finput-charset=UTF-8 -fexec-charset=UTF-8'
alias ls='ls --color'
