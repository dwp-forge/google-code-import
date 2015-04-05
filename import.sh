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
{(
    echo "Cloning SVN repository to Git ${git_path}"

    if [[ -e "${git_path}" ]] ; then
        rm -rf "${git_path}"
    fi

    git svn clone "file://${svn_path}" -T trunk -b branches -t tags --authors-file="${base_path}/authors.txt" --prefix=svn/ "${git_path}"

    cd "${git_path}"

    git config user.name "Mykola Ostrovskyy"
    git config user.email "spambox03@mail.ru"
)}

delete_refs()
{
    git for-each-ref --format="%(refname)" "$1" | xargs -rn 1 git update-ref -d
}

filter_branch()
{
    git filter-branch "$@"
    delete_refs "refs/original/"
}

reset_dates()
{
    filter_branch --env-filter 'export GIT_COMMITTER_DATE="${GIT_AUTHOR_DATE}"' "$@"
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

    local commit_range

    if [[ "${commits}" != "" ]] ; then
        commit_range="${git_branch}~${commits}..${git_branch}"
    else
        commit_range="${git_branch}"
    fi

    filter_branch --msg-filter "php \"${base_path}/rename.php\"" "${commit_range}"
    reset_dates "${commit_range}"
)}

get_revision_commit()
{
    git log --oneline "$1" | grep -P "^[0-9a-f]+ $2(:|$)" | sed -re "s/^([0-9a-f]+) .*/\1/"
}

rebase_branch()
{(
    cd "${git_path}"

    local branch="$1"
    local commits="$2"
    local target_branch="$3"
    local revision="$4"
    local subtree="$5"
    local target_commit=$(get_revision_commit "${target_branch}" ${revision})

    echo "Rebasing branch ${branch}"

    if [[ "${target_commit}" == "" ]] ; then
        echo "Failed to find revision ${revision} on ${target_branch}"
        return 1
    fi

    if [[ "${subtree}" != "" ]] ; then
        git rebase --keep-empty --strategy-option="subtree=${subtree}" --onto ${target_commit} "${branch}~${commits}" "${branch}" || return 1
    else
        git rebase --keep-empty --onto ${target_commit} "${branch}~${commits}" "${branch}" || return 1
    fi

    reset_dates "${branch}~${commits}..${branch}"
)}

merge_branch()
{(
    cd "${git_path}"

    local branch="$1"
    local target_branch="$2"
    local revision="$3"
    local target_commit=$(get_revision_commit "${target_branch}" ${revision})

    echo "Merging branch ${branch} into ${target_branch}"

    if [[ "${target_commit}" == "" ]] ; then
        echo "Failed to find revision ${revision} on ${target_branch}"
        return 1
    fi

    local checkout_commit

    if [[ "${4}" != "" && "${5}" != "" ]] ; then
        checkout_commit=$(get_revision_commit "${4}" ${5})

        if [[ "${checkout_commit}" == "" ]] ; then
            echo "Failed to find revision ${5} on ${4}"
            return 1
        fi
    else
        checkout_commit=${target_commit}~1
    fi

    (
        export GIT_MESSAGE=$(git log ${target_commit} -1 --pretty=format:%B)
        export GIT_AUTHOR_DATE=$(git log ${target_commit} -1 --pretty=format:%ad)
        export GIT_COMMITTER_DATE="${GIT_AUTHOR_DATE}"

        git checkout ${checkout_commit}
        git merge "${branch}" --commit -m "${GIT_MESSAGE}" ||
        (
            git apply "${base_path}/patches/${revision}.patch" &&
            git commit -am "${GIT_MESSAGE}"
        )
    ) || return 1

    local merge_commit=$(git log -1 --pretty=format:%h)

    git rebase --onto ${merge_commit} ${target_commit} "${target_branch}" &&
    reset_dates "${merge_commit}..${target_branch}"
)}

create_temp_branch()
{(
    cd "${git_path}"

    local branch="$1"
    local revision="$2"
    local commit=$(get_revision_commit "${branch}" ${revision})

    if [[ "${commit}" == "" ]] ; then
        echo "Failed to find revision ${revision} on ${branch}"
        return 1
    fi

    if [[ "$(git rev-parse --verify --quiet "temp-${revision}")" != "" ]] ; then
        git branch -D "temp-${revision}"
    fi

    git branch "temp-${revision}" ${commit}
)}

delete_branch()
{(
    cd "${git_path}"

    local branch="$1"

    echo "Deleting branch ${branch}"

    delete_refs "refs/remotes/${branch}*"
)}

splice_branch()
{
    local source_branch="$1"
    local branch="$2"
    local commits="$3"
    local subtree="$4"
    local target_branch="$5"
    local target_revision="$6"

    update_branch "${source_branch}" "${branch}" ${commits} &&
    rebase_branch "${branch}" ${commits} "${target_branch}" ${target_revision} "${subtree}" &&
    delete_branch "${source_branch}"
}

splice_tag()
{
    splice_branch "$1" "$2" 1 "" "$3" "$4"
}

clean_repo()
{(
    cd "${git_path}"

    echo "Cleaning repository ${git_path}"

    git reset --hard &&
    delete_refs "refs/original/" &&
    delete_refs "refs/heads/temp-*" &&
    git reflog expire --expire=now --all &&
    git gc --aggressive --prune=now &&
    git checkout master
)}

clone_repo()
{(
    local clone="$1"

    echo "Cloning repository ${git_path} to ${clone}"

    if [[ -e "${clone}" ]] ; then
        rm -rf "${clone}"
    fi

    cp -R "${git_path}" "${clone}"
)}

create_tags()
{(
    cd "${git_path}"

    echo "Creating tags for ${plugin}"

    local branch

    for branch in $(git for-each-ref --format="%(refname)" "refs/heads/tags-${plugin}-*" | sed -re "s/refs\/heads\///") ; do
        local tag=t.$(echo ${branch} | sed -re "s/tags-${plugin}-(.+)/\1/")

        (
            export GIT_MESSAGE=$(git log ${branch} -1 --pretty=format:%B | sed -re "s/^r[0-9]+: //")
            export GIT_AUTHOR_DATE=$(git log ${branch} -1 --pretty=format:%ad)
            export GIT_COMMITTER_DATE="${GIT_AUTHOR_DATE}"

            local release=$(echo "${GIT_MESSAGE}" | grep Release | sed -re "s/Release (of )?([-0-9]+).*/\2/")

            if [[ "${release}" != "" ]] ; then
                tag="v.${release}"
            fi

            git tag -a "${tag}" -m "${GIT_MESSAGE}" "${branch}~1"
        ) || return 1
    done

    delete_refs "refs/heads/tags-${plugin}-*"
)}

trim_branches()
{(
    cd "${git_path}"

    echo "Trimming branches for ${plugin}"

    for branch in $(git branch -a | grep -vP "master|${plugin}-") ; do
        git branch -D ${branch}
    done

    filter_branch --tag-name-filter cat --prune-empty --subdirectory-filter "${plugin}" -- --all
    reset_dates -- --all
)}

export_plugin()
{(
    local plugin="$1"
    local plugin_repo="${base_path}/${plugin}"

    clone_repo "${plugin_repo}"

    git_path="${plugin_repo}"

    create_tags
    trim_branches
)}

main()
{
    local base_path=$(readlink -f $(dirname $BASH_SOURCE))
    local svn_url="http://dwp-forge.googlecode.com/svn/"
    local svn_path="${base_path}/dwp-forge-svn"
    local git_path="${base_path}/dwp-forge-git"

    fetch_svn || return 1
    clone_svn_to_git || return 1

    update_branch "svn/trunk" "master" &&
    delete_branch "svn/trunk"

    splice_branch "svn/columns3" "columns-v3" 46 "columns" "master" r76

    splice_branch "svn/refnotes-inheritance" "refnotes-inheritance" 13 "refnotes" "master" r115
    merge_branch "refnotes-inheritance" "master" r143

    splice_branch "svn/columns-odt_support" "columns-odt-support" 5 "columns" "columns-v3" r226
    merge_branch "columns-odt-support" "columns-v3" r233

    splice_branch "svn/refnotes-reference_database" "refnotes-reference-database" 15 "refnotes" "master" r244
    merge_branch "refnotes-reference-database" "master" r270

    splice_branch "svn/qna-custom_headers" "qna-custom-headers" 8 "qna" "master" r327
    merge_branch "qna-custom-headers" "master" r337

    splice_branch "svn/refnotes-refdb_cache_dependency" "refnotes-refdb-cache-dependency" 4 "refnotes" "master" r343
    merge_branch "refnotes-refdb-cache-dependency" "master" r352

    update_branch "svn/refnotes-structured_references" "refnotes-structured-references" 55
    update_branch "svn/refnotes-dual_core" "refnotes-dual-core" 9
    update_branch "svn/refnotes-heavy_action" "refnotes-heavy-action" 23

    create_temp_branch "refnotes-structured-references" r413
    create_temp_branch "refnotes-structured-references" r421
    create_temp_branch "refnotes-structured-references" r433
    create_temp_branch "refnotes-structured-references" r453

    rebase_branch "temp-r413" 41 "master" r361 "refnotes"
    rebase_branch "refnotes-dual-core" 9 "temp-r413" r409 "refnotes"
    merge_branch "refnotes-dual-core" "temp-r421" r421 "temp-r413" r413
    rebase_branch "temp-r433" 6 "temp-r421" r421 "refnotes"
    rebase_branch "refnotes-heavy-action" 23 "temp-r433" r426 "refnotes"
    merge_branch "refnotes-heavy-action" "temp-r453" r453 "temp-r433" r433
    rebase_branch "refnotes-structured-references" 6 "temp-r453" r453 "refnotes"
    merge_branch "refnotes-structured-references" "master" r461

    delete_branch "svn/refnotes-dual_core"
    delete_branch "svn/refnotes-heavy_action"
    delete_branch "svn/refnotes-structured_references"

    splice_tag "svn/tags/columns-0901311636" "tags-columns-0901311636" "master" r46
    splice_tag "svn/tags/columns-0903011954" "tags-columns-0903011954" "columns-v3" r85
    splice_tag "svn/tags/columns-0903151954" "tags-columns-0903151954" "columns-v3" r110
    splice_tag "svn/tags/columns-0904041335" "tags-columns-0904041335" "columns-v3" r137
    splice_tag "svn/tags/columns-0908221657" "tags-columns-0908221657" "columns-v3" r237
    splice_tag "svn/tags/columns-0908301834" "tags-columns-0908301834" "columns-v3" r250
    splice_tag "svn/tags/columns-1209232308" "tags-columns-1209232308" "columns-v3" r508
    splice_tag "svn/tags/columns-1210131603" "tags-columns-1210131603" "columns-v3" r511

    splice_tag "svn/tags/batchedit-0810251603" "tags-batchedit-0810251603" "master" r20
    splice_tag "svn/tags/batchedit-0810270018" "tags-batchedit-0810270018" "master" r29
    splice_tag "svn/tags/batchedit-0812071806" "tags-batchedit-0812071806" "master" r35
    splice_tag "svn/tags/batchedit-0902141955" "tags-batchedit-0902141955" "master" r68

    splice_tag "svn/tags/tablewidth-0902141526" "tags-tablewidth-0902141526" "master" r62
    splice_tag "svn/tags/tablewidth-1011181526" "tags-tablewidth-1011181526" "master" r399
    splice_tag "svn/tags/tablewidth-1312031348" "tags-tablewidth-1312031348" "master" r518

    splice_tag "svn/tags/replace-0904131936" "tags-replace-0904131936" "master" r148

    splice_tag "svn/tags/changes-0909162356" "tags-changes-0909162356" "master" r290

    splice_tag "svn/tags/qna-0912131824" "tags-qna-0912131824" "master" r339
    splice_tag "svn/tags/qna-1502160108" "tags-qna-1502160108" "master" r523

    splice_tag "svn/tags/refnotes-0903181339" "tags-refnotes-0903181339" "master" r111
    splice_tag "svn/tags/refnotes-0908011250" "tags-refnotes-0908011250" "master" r222
    splice_tag "svn/tags/refnotes-0909121625" "tags-refnotes-0909121625" "master" r275
    splice_tag "svn/tags/refnotes-0910111658" "tags-refnotes-0910111658" "master" r308
    splice_tag "svn/tags/refnotes-1004052043" "tags-refnotes-1004052043" "master" r361
    splice_tag "svn/tags/refnotes-1207151516" "tags-refnotes-1207151516" "master" r504

    delete_branch "svn/tags/refnotes-0908011230"
    delete_branch "svn/tags/refnotes-0910111319"
    delete_branch "svn/tags/refnotes-1111071939"
    delete_branch "svn/tags/refnotes-1204230046"
    delete_branch "svn/tags/refnotes-1204291450"

    clean_repo

    export_plugin "batchedit"
    export_plugin "changes"
    export_plugin "color"
}

main "$@"
