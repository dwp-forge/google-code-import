#!/bin/bash

fetch_svn()
{
    echo "Fetching SVN repository to ${svn_path}"

    if [[ -e "${svn_path}" ]] ; then
        rm -rf "${svn_path}"
    fi

    svnadmin create "${svn_path}"

    local hook="${svn_path}/hooks/pre-revprop-change"

    echo '#!/bin/sh' > "${hook}"
    echo 'exit 0' >> "${hook}"

    chmod +x "${hook}"

    svnsync init "file://${svn_path}" "${svn_url}"
    svnsync sync "file://${svn_path}"
}

clone_svn_to_git()
{
    echo "Cloning SVN repository to Git ${git_path}"

    if [[ -e "${git_path}" ]] ; then
        rm -rf "${git_path}"
    fi

    git svn clone "file://${svn_path}" -T trunk -b branches -t tags --authors-file="${base_path}/authors.txt" --prefix=svn/ "${git_path}"
}

filter_branch()
{
    git filter-branch "$@"
    git for-each-ref --format="%(refname)" refs/original/ | xargs -n 1 git update-ref -d
}

update_branch()
{(
    cd "${git_path}"

    local svn_branch="$1"
    local git_branch="$2"
    local commits="$3"

    echo "Updating branch ${svn_branch}"

    if [[ "$(git rev-parse --verify --quiet "${svn_branch}")" == "" ]] ; then
        echo "Source branch ${svn_branch} is not found"
        return 1
    fi

    if [[ "$(git rev-parse --verify --quiet "${git_branch}")" == "" ]] ; then
        git checkout -b "${git_branch}" "${svn_branch}"
    else
        git checkout "${git_branch}"
        git reset --hard "${svn_branch}"
    fi

    if [[ "${commits}" != "" ]] ; then
        filter_branch --msg-filter "php \"${base_path}/rename.php\"" "${git_branch}~${commits}..${git_branch}"
    else
        filter_branch --msg-filter "php \"${base_path}/rename.php\"" "${git_branch}"
    fi
)}

rebase_branch()
{(
    cd "${git_path}"

    local branch="$1"
    local commits="$2"
    local target_branch="$3"
    local revision="$4"
    local target_commit=$(git log --oneline "${target_branch}" | grep -P " ${revision}[: ]" | sed -re "s/^([0-9a-f]+) .*/\1/")

    echo "Rebasing branch ${branch}"

    if [[ "${target_commit}" == "" ]] ; then
        echo "Failed to find revision ${revision} on ${target_branch}"
        return 1
    fi

    git rebase --keep-empty --onto "${target_commit}" "${branch}~${commits}" "${branch}"
)}

delete_branch()
{(
    cd "${git_path}"

    local branch="$1"

    echo "Deleting branch ${branch}"

    git for-each-ref --format="%(refname)" "refs/remotes/${branch}*" | xargs -n 1 git update-ref -d
)}

splice_branch()
{(
    local source_branch="$1"
    local branch="$2"
    local commits="$3"
    local target_branch="$4"
    local target_revision="$5"

    update_branch "${source_branch}" "${branch}" ${commits} &&
    rebase_branch "${branch}" ${commits} "${target_branch}" ${target_revision} &&
    delete_branch "${source_branch}"
)}

main()
{
    local base_path=$(readlink -f $(dirname $BASH_SOURCE))
    local svn_url="http://dwp-forge.googlecode.com/svn/"
    local svn_path="${base_path}/dwp-forge-svn"
    local git_path="${base_path}/dwp-forge-git"

    fetch_svn || return 1
    clone_svn_to_git || return 1

    update_branch "svn/trunk" "master"

    splice_branch "svn/tags/batchedit-0810251603" "tags-batchedit-0810251603" 1 "master" r20
    splice_branch "svn/tags/batchedit-0810270018" "tags-batchedit-0810270018" 1 "master" r29
    splice_branch "svn/tags/batchedit-0812071806" "tags-batchedit-0812071806" 1 "master" r35
    splice_branch "svn/tags/batchedit-0902141955" "tags-batchedit-0902141955" 1 "master" r68
}

main "$@"
