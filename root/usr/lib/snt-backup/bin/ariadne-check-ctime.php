#!/usr/bin/env php
<?php

	$ariadne = $argv[1].'/lib/';
	$site = $argv[2];
	$mtime = $argv[3];
	if(!is_dir($ariadne)){
		echo "geef een ariadne dir mee als argument\n";
		exit(0);
	}
	if(!isset($site)){
		echo "site required\n";
		exit(0);
	}

	$ARLoader = 'cmd';
	$currentDir = getcwd();

	if (file_exists($ariadne."/bootstrap.php")) {
		// ariadne 9.0
		require_once($ariadne."/bootstrap.php");
	} else {
		// ariadne pre 9.0
		if (!@include_once($ariadne."/configs/ariadne.phtml")) {
			chdir(substr($_SERVER['PHP_SELF'], 0, strrpos($_SERVER['PHP_SELF'], '/')));
			if(!include_once($ariadne."/configs/ariadne.phtml")){
				echo "could not open ariadne.phtml";
				exit(1);
			}
		}
		require($ariadne."/configs/store.phtml");
		require($ariadne."/includes/loader.cmd.php");
		require($ariadne."/stores/".$store_config["dbms"]."store.phtml");
		include($ariadne."/nls/".$AR->nls->default);

	}

	$inst_store = $store_config["dbms"]."store";
	$store=new $inst_store($root,$store_config);

	/* now load a user (admin in this case)*/
	$login = "admin";
	$query = "object.implements = 'puser' and login.value='$login'";
	$AR->user = current($store->call('system.get.phtml', '', $store->find('/system/users/', $query)));

	/* do your stuff here */
	$count = $store->count_find($site," time.mtime > $mtime ");

	$store->close();
	exit($count?1:0);
?>
