git-resign() {
    local auto_yes=0 do_fetch=0 a
    for a in "$@"; do
        case "$a" in
            -y|--yes) auto_yes=1 ;;
            --fetch)  do_fetch=1 ;;
        esac
    done

    # 1. In a git repo?
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "error: not inside a git repository" >&2; return 1
    fi

    # Clean tree?
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "error: uncommitted changes present; commit or stash first" >&2; return 1
    fi

    # 2. Configured user
    local cfg_email cfg_name
    cfg_email=$(git config user.email)
    cfg_name=$(git config user.name)
    [ -z "$cfg_email" ] && { echo "error: git user.email not configured" >&2; return 1; }
    echo "Current git user: ${cfg_name:-<no name>} <$cfg_email>"
    [ -z "$(git config user.signingkey)" ] && \
        echo "warning: user.signingkey not set; relying on gpg default key" >&2

    # Upstream (published) boundary — the real force-push guard
    local upstream range have_upstream=1
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || have_upstream=0
    if [ "$have_upstream" -eq 1 ]; then
        [ "$do_fetch" -eq 1 ] && git fetch --quiet
        echo "Upstream: $upstream (commits already there will NOT be rewritten)"
        range='@{u}..HEAD'
    else
        echo "warning: no upstream tracking branch; cannot verify what's already pushed." >&2
        if [ "$auto_yes" -ne 1 ]; then
            echo "         re-run with --yes to proceed using author/signature checks only." >&2
            return 1
        fi
        range='HEAD'
    fi

    # 3. Walk the safe (unpushed) range newest-first. --no-show-signature keeps
    #    gpg verification text out of stdout; the hash guard skips any stray line.
    local count=0 base="" hit_boundary=0 sha email sig
    while IFS=$'\t' read -r sha email sig; do
        case "$sha" in ""|*[!0-9a-f]*) continue ;; esac   # not a commit hash → ignore
        if [ "$email" != "$cfg_email" ]; then base=$sha; hit_boundary=1; break; fi
        if [ "$sig" != "N" ];          then base=$sha; hit_boundary=1; break; fi
        count=$((count + 1))
    done < <(git log --no-show-signature --format='%H%x09%ae%x09%G?' "$range" 2>/dev/null)

    if [ "$count" -eq 0 ]; then
        echo "Nothing to do: no unsigned commits of yours ahead of the safe boundary."
        return 0
    fi

    if [ "$hit_boundary" -eq 0 ]; then
        if [ "$have_upstream" -eq 1 ]; then base=$(git rev-parse '@{u}'); else base=""; fi
    fi

    echo
    echo "Will re-sign $count commit(s):"
    git --no-pager log --no-show-signature --format='  %h  %an  %s' -n "$count" HEAD
    echo

    local merges
    if [ -n "$base" ]; then merges=$(git log --no-show-signature --merges --format='%h' "$base..HEAD")
    else                    merges=$(git log --no-show-signature --merges --format='%h' HEAD); fi
    if [ -n "$merges" ]; then
        echo "warning: range contains merge commit(s); rebase may flatten them:" >&2
        echo "$merges" | sed 's/^/  /' >&2; echo
    fi

    if [ "$auto_yes" -ne 1 ]; then
        printf "Rewrites these (local, unpushed) commits. Continue? [y/N] "
        local reply; read -r reply
        case "$reply" in [yY]|[yY][eE][sS]) ;; *) echo "aborted"; return 1 ;; esac
    fi

    # 4. Re-sign
    if [ -n "$base" ]; then
        git rebase "$base" --exec 'git commit --amend --no-edit --no-verify -S'
    else
        git rebase --root  --exec 'git commit --amend --no-edit --no-verify -S'
    fi
}
