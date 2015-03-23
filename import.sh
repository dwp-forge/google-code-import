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

main()
{
    local base_path=$(readlink -f $(dirname $BASH_SOURCE))
    local svn_url="http://dwp-forge.googlecode.com/svn/"
    local svn_path="${base_path}/dwp-forge-svn"
    local git_path="${base_path}/dwp-forge-git"

    fetch_svn || return 1
    clone_svn_to_git || return 1
}

main "$@"
