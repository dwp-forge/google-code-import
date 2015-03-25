<?php

// Usage:
//   git filter-branch -f --msg-filter 'php <absolute-path>/rename.php'

function get_svn_revision(&$message) {
    $git_svn_id = array_pop($message);

    if (preg_match("/git-svn-id.+@(\d+).+/", $git_svn_id, $matches) == 0) {
        error_log("\nCannot detect SVN id\n");
        exit(1);
    }

    return $matches[1];
}

function is_empty($message) {
    return count($message) == 0 || empty(trim($message[0]));
}

function remove_minors($message) {
    static $minors = array(
        "/^\s*$/",
        "/^. Spaces\n/",
        "/^. Typo\n/",
        "/^. Version\n/",
        "/^. Clean-up\n/",
        "/^. Comments\n/",
        "/^. Formatting\n/",
        "/^. Naming\n/"
    );

    while (count($message) > 1) {
        $removed = false;

        foreach ($minors as $minor) {
            for ($i = 0; $i < count($message); $i++) {
                if (preg_match($minor, $message[$i]) == 1) {
                    unset($message[$i]);
                    $message = array_values($message);
                    $removed = true;
                    break 2;
                }
            }
        }

        if (!$removed) {
            break;
        }
    }

    return $message;
}

function translate_title($message, $revision) {
    static $replace = array(
        "/^(?:20|26|128|135|208|210|290|300|302):. (.+)\n/" => "\\1",
        "/^\d+:! (Allow|Check|Ensure|Fix|Make|Prevent|Reset|Suppress|Verify)( .+)\n/" => "\\1\\2",
        "/^\d+:\* Comments\n/" => "Updated comments",
        "/^\d+:\* Naming\n/" => "Updated naming",
        "/^\d+:\* Version\n/i" => "Version update",
        "/^\d+:\* Version info\n/" => "Version update",
        "/^\d+:\+ (\w)(.+)\n/" => "Added <\\1>\\2",
        "/^\d+:! (\w)(.+)\n/" => "Fixed <\\1>\\2",
        "/^\d+:- (\w)(.+)\n/" => "Removed <\\1>\\2",
        "/^\d+:\* (.+)\n/" => "\\1"
    );

    $message[0] = preg_replace(array_keys($replace), array_values($replace), $revision . ":" . $message[0]);
    $message[0] = preg_replace_callback("/<(\w)>/", function ($matches) { return strtolower($matches[1]); }, $message[0]);

    return $message;
}

function translate($message, $revision) {
    static $replace = array(
        "2" => "Added columns plugin",
        "9" => array("Fixed preview of big text blocks\n\n", "Text will wrap to multiple lines.\n"),
        "11" => array("+ Application request parsing\n", "+ Indication of applied matches\n"),
        "38" => "Version update",
        "40" => "Updated formatting and comments",
        "68" => "Added View & Edit links",
        "69" => "Release of 2009-02-14",
        "86" => array("Release of 2009-03-01\n\n", "First alpha version of columns3.\n"),
        "124" => array("Fixed sub-namespace scoping\n\n", "Use the start of the parent namespace's current scope as\nthe sub-namespace creation point.\n"),
        "125" => array("Sort style blocks before insertion into calls\n\n", "This ensures that a parent namespace is styled before\nits sub-namespaces.\n"),
        "128" => array("Fixed section editing\n\n", "Look-ahead patterns are removed to allow syntax matching\nduring section editing.\n"),
        "134" => array("buildLayout() refactoring\n\n", "Preparation for continuations support.\n"),
        "139" => array("Merge tracking of creation and rendering instructions with scope tracking\n"),
        "143" => array("Added namespace inheritance implementation\n\n", "Merged from refnotes-inheritance branch.\n"),
        "155" => array("Embed notes on every occurrence\n\n", "Don't remove embedded notes from the array and embed them on every\n", "occurrence. This will prevent loosing the note text in the next scope.\n"),
        "156" => "More spaces",
        "204" => array("Scroll to the top of the page after sending the settings\n\n", "This allows to show the communication status.\n"),
        "225" => array("Reset the state before parsing\n\n", "Support for multiple handle() calls, which can happen\nwith Include plugin.\n"),
        "228" => "First column knows width of each column of the block",
        "232" => array("Omit width attribute for 100% tables\n\n", "Rely on align=margins instead.\n"),
        "234" => array("Keep track of opened sections (issue 1)\n\n", "Fixes broken page layout if the first heading is within a column.\n"),
        "304" => array("Fixed general settings (issue 7)\n\n", "Settings from the general configuration section were ignored.\n"),
        "313" => "Initial commit",
        "322" => "Fixed PHP5 syntax",
        "346" => array("Reset internal state before handling every PARSER_HANDLER_DONE event\n\n", "Include plugin compatibility."),
        "350" => array("Fixed page cache invalidation\n\n", "Make sure that metadata for currently processed page affects caching\nonly of that page.\n"),
        "353" => array("Removed definition of DOKU_PLUGIN\n\n", "It should be already defined when plugin is loaded.\n"),
        "354" => array("Fixed first reference instruction lookup\n\n", "Look for the first reference instruction i.s.o. assuming\nthat it will be the first one in the calls array.\n"),
        "401" => "Fixed JSON corruprion by webhost servers",
        "466" => "Added BibTeX parser",
        "488" => "Move version information to plugin.info.txt",
        "498" => "Added 'month' field support",
        "504" => "Updated includes",
    );

    if (array_key_exists($revision, $replace)) {
        if (is_array($replace[$revision])) {
            $message = $replace[$revision];
        } else {
            $message = array($replace[$revision]);
        }
    } elseif (!is_empty($message) && preg_match("/^[-+*!]/", $message[0]) == 1) {
        $majors = remove_minors($message);

        if (count($majors) == 1) {
            $message = translate_title($majors, $revision);
        }
    }

    return $message;
}

function update($message, $revision) {
    // Remove empty line at the end
    array_pop($message);

    $message = translate($message, $revision);

    if (!is_empty($message)) {
        if (preg_match("/^[-+*!]/", $message[0]) == 0) {
            $message[0] = preg_replace("/(.+)\.(\s*)$/", "\\1\\2", $message[0]);
            $message[0] = "r$revision: ${message[0]}";
        } else {
            array_unshift($message, "r$revision\n\n");
        }
    } else {
        $message = array("r$revision");
    }

    return $message;
}

$message = file("php://stdin");
$revision = get_svn_revision($message);

error_log("\nRevision $revision");

print(implode(update($message, $revision)));
