#!/usr/bin/env php
<?php
	$ariadne = $argv[1].'/lib/';
	$dumpdir = $argv[2];

	if(!is_dir($ariadne)){
		echo "geef een ariadne dir mee als argument\n";
		exit(0);
	}
	if(!isset($dumpdir)){
		echo "dumpdir required\n";
		exit(0);
	}

	/*
	  support classes
	  class output-redirect

	*/
	class outputRedirect {
		private $fd;

		public function __construct() {
			ob_start(array($this,'handler'),16);
			$this->fd = fopen('php://stderr','w');
		}

		public function handler($buffer) {
			fwrite($this->fd,$buffer);
			return '';
		}

		public function __destruct(){
			$this->end();
		}

		public function end() {
			if (is_resource($this->fd)){
				ob_flush();
				ob_end_clean();
				fclose($this->fd);
			}
		}
	}

	$oob = new outputRedirect();
	
	$ARLoader = 'cmd';
	$currentDir = getcwd();

	if (file_exists($ariadne."/bootstrap.php")) {
		// ariadne 9.0
		require_once($ariadne."/bootstrap.php");
	} else {
		// ariadne pre 9.0
		if (!@include_once($ariadne."/configs/ariadne.phtml")) {
			echo "could not open ariadne.phtml";
			exit(1);
		}
		require($ariadne."/configs/store.phtml");
		require($ariadne."/includes/loader.cmd.php");
		require($ariadne."/stores/".$store_config["dbms"]."store.phtml");
		require($ariadne."/ar.php");
		require($ariadne."/nls/".$AR->nls->default);

	}
	require($ariadne."/configs/axstore.phtml");
	require($ariadne."/stores/axstore.phtml");

	set_time_limit(0);

	if( isset( $ARCurrent->options['temp']) && 
		is_dir($ARCurrent->options['temp']) &&
		is_writeable($ARCurrent->options['temp'])
		){
		$ax_config['temp'] = $ARCurrent->options['temp'];
	}

	$ARCurrent->nolangcheck = true;

	$ax_config["database"]='php://stdout';
	$ax_config["writeable"]=true;

	$srcpath=$dumpdir;
	//$ARCurrent->options["verbose"]=true;

	$importStore=new axstore("", $ax_config);
	if (!$importStore->error) {
		$inst_store = $store_config["dbms"]."store";
		$store=new $inst_store($root,$store_config);

		/* now load a user (admin in this case)*/
		$login = "admin";
		$query = "object.implements = 'puser' and login.value='$login'";
		$AR->user = current($store->call('system.get.phtml', '', $store->find('/system/users/', $query)));

		$ARCurrent->importStore = &$importStore;
		$callArgs["srcpath"]    = $srcpath;
		$callArgs["destpath"]   = null;
		$error=current($store->call("system.export.phtml", $callArgs, $store->get("/")));
		$importStore->database = '/dev/stdout';
		$oob->end();

		$importStore->close();

		// stream tar here
	} else {
		// special handling here
		$importStore->writeable = false;
		$importStore->close();
	}

	unset($oob);

