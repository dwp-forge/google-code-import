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
        "/^. Spaces\n/",
        "/^. Version\n/",
        "/^. Clean-up\n/",
        "/^. Comments\n/",
        "/^. Formatting\n/",
        "/^. Naming\n/"
    );

    while (count($message) > 1) {
        foreach ($minors as $minor) {
            for ($i = 0; $i < count($message); $i++) {
                if (preg_match($minor, $message[$i]) == 1) {
                    unset($message[$i]);
                    $message = array_values($message);
                    break 2;
                }
            }
        }

        break;
    }

    return $message;
}

function translate_title($message, $revision) {
    static $replace = array(
        "/^(?:20|26|128|135|290|300|302):. (.+)\n/" => "\\1",
        "/^\d+:! (?:Allow|Ensure|Fix|Make|Prevent|Reset|Suppress|Verify)( .+)\n/" => "\\1\\2",
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
        "11" => array("+ Application request parsing\n", "+ Indication of applied matches\n"),
        "38" => "Version update",
        "40" => "Updated formatting and comments",
        "90" => "Clean-up",
        "156" => "More spaces",
        "304" => array("Fixed general settings (issue 7)\n\n", "Settings from the general configuration section were ignored\n"),
        "313" => "Initial commit",
        "322" => "Fixed PHP5 syntax",
        "353" => array("Removed definition of DOKU_PLUGIN\n\n", "It should be already defined when plugin is loaded\n"),
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
    } else {
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

    $has_title = (preg_match("/^\w/", $message[0]) == 1);

    if (!$has_title) {
        $message = translate($message, $revision);
        $has_title = (preg_match("/^\w/", $message[0]) == 1);
    }

    if ($has_title) {
        $message[0] = preg_replace("/(.+)\.(\s?)$/", "\\1\\2", $message[0]);
        $message[0] = "r$revision: ${message[0]}";
    } else {
        array_unshift($message, "r$revision\n\n");
    }

    return $message;
}

$message = file("php://stdin");
$revision = get_svn_revision($message);

error_log("\nRevision $revision");

$message = is_empty($message) ? array("r$revision") : update($message, $revision);

print(implode($message));
