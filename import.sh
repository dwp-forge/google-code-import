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

    echo "Updating branch ${svn_branch}"

    if [[ "$(git rev-parse --verify --quiet "${git_branch}")" == "" ]] ; then
        git checkout -b "${git_branch}" "${svn_branch}"
    else
        git checkout "${git_branch}"
        git reset --hard "${svn_branch}"
    fi

    filter_branch --msg-filter "php \"${base_path}/rename.php\""
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
}

main "$@"
